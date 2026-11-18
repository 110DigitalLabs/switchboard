import Foundation

/// A minimal MCP client over Streamable HTTP: initialize handshake,
/// `tools/list` and `tools/call`, session IDs, JSON and SSE replies, and
/// one token refresh on 401.
actor MCPClient {
    static let protocolVersion = "2025-06-18"

    let endpoint: URL
    private let authorizer: MCPAuthorizing
    private let session: URLSession
    private let clientVersion: String

    private var sessionID: String?
    private var negotiatedVersion: String?
    private var initializing: Task<Void, Error>?
    private var nextID = 1

    init(endpoint: URL, authorizer: MCPAuthorizing, session: URLSession = .shared,
         clientVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.endpoint = endpoint
        self.authorizer = authorizer
        self.session = session
        self.clientVersion = clientVersion
    }

    func listTools() async throws -> [MCPTool] {
        var tools: [MCPTool] = []
        var cursor: String?
        repeat {
            let params: JSONValue? = cursor.map { ["cursor": .string($0)] }
            let result = try await call(method: "tools/list", params: params)
            tools += (result["tools"]?.arrayValue ?? []).compactMap(MCPTool.init(json:))
            cursor = result["nextCursor"]?.nonEmptyString
        } while cursor != nil
        return tools
    }

    func callTool(_ name: String, arguments: [String: JSONValue] = [:]) async throws -> MCPToolResult {
        let result = try await call(method: "tools/call",
                                    params: ["name": .string(name), "arguments": .object(arguments)])
        return MCPToolResult(json: result)
    }

    /// Forgets the server session, e.g. after sign-out.
    func reset() {
        sessionID = nil
        negotiatedVersion = nil
        initializing?.cancel()
        initializing = nil
    }

    // MARK: - Requests

    private func call(method: String, params: JSONValue?) async throws -> JSONValue {
        try await ensureInitialized()
        do {
            return try await send(method: method, params: params)
        } catch MCPError.sessionExpired {
            reset()
            try await ensureInitialized()
            return try await send(method: method, params: params)
        }
    }

    private func ensureInitialized() async throws {
        if negotiatedVersion != nil { return }
        if let initializing { return try await initializing.value }
        let task = Task { try await self.performInitialize() }
        initializing = task
        defer { initializing = nil }
        try await task.value
    }

    private func performInitialize() async throws {
        let result = try await send(method: "initialize", params: [
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": ["name": "Switchboard", "version": .string(clientVersion)],
        ])
        negotiatedVersion = result["protocolVersion"]?.nonEmptyString ?? Self.protocolVersion
        try await notify(method: "notifications/initialized")
    }

    private func notify(method: String) async throws {
        let body = try JSONRPC.notification(method: method).encoded()
        let (_, response) = try await perform(body: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw MCPError.http(status: status) }
    }

    private func send(method: String, params: JSONValue?) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let body = try JSONRPC.request(id: id, method: method, params: params).encoded()
        let (bytes, response) = try await perform(body: body)
        guard let http = response as? HTTPURLResponse else { throw MCPError.malformedResponse("not HTTP") }
        if method == "initialize", let header = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionID = header
        }
        switch http.statusCode {
        case 200..<300: break
        case 404 where sessionID != nil && method != "initialize": throw MCPError.sessionExpired
        default: throw MCPError.http(status: http.statusCode)
        }
        if MCPResponseParser.isEventStream(contentType: http.value(forHTTPHeaderField: "Content-Type")) {
            return try await Self.readEventStream(bytes, id: id)
        }
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return try MCPResponseParser.parseJSON(data, id: id)
    }

    /// Sends one POST with the current token, refreshing once on 401.
    private func perform(body: Data) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var token = try await authorizer.accessToken()
        var refreshed = false
        while true {
            let (bytes, response) = try await session.bytes(for: request(body: body, token: token))
            guard (response as? HTTPURLResponse)?.statusCode == 401 else { return (bytes, response) }
            guard !refreshed else { throw MCPError.unauthorized }
            refreshed = true
            token = try await authorizer.refreshAccessToken(rejected: token)
        }
    }

    private func request(body: Data, token: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let negotiatedVersion { request.setValue(negotiatedVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        return request
    }

    /// Reads events until the response to `id` arrives, so a server that
    /// keeps the stream open does not stall the call.
    private static func readEventStream(_ bytes: URLSession.AsyncBytes, id: Int) async throws -> JSONValue {
        var parser = SSEParser()
        var chunk = Data()
        for try await byte in bytes {
            chunk.append(byte)
            guard byte == 0x0A else { continue }
            for event in parser.feed(chunk) {
                if let result = try MCPResponseParser.result(in: event, id: id) { return result }
            }
            chunk.removeAll(keepingCapacity: true)
        }
        _ = parser.feed(chunk)
        for event in parser.finish() {
            if let result = try MCPResponseParser.result(in: event, id: id) { return result }
        }
        throw MCPError.noResponse
    }
}
