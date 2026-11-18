import Foundation
import Testing
@testable import Switchboard

/// Drives MCPClient against a scripted HTTP server.
@Suite(.serialized)
struct MCPClientTests {
    @Test func handshakeCarriesSessionIDAndParsesSSE() async throws {
        let server = StubServer { request, body in
            switch body["method"]?.stringValue {
            case "initialize":
                return .json(["jsonrpc": "2.0", "id": body["id"]!,
                              "result": ["protocolVersion": "2025-06-18", "capabilities": [:]]],
                             headers: ["Mcp-Session-Id": "sess-1"])
            case "notifications/initialized":
                #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == "sess-1")
                return .accepted
            default:
                #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == "sess-1")
                #expect(request.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t1")
                let message = try! String(decoding: JSONValue.object([
                    "jsonrpc": "2.0", "id": body["id"]!,
                    "result": ["tools": [["name": "list_issues"]]]]).encoded(), as: UTF8.self)
                return .sse("event: message\ndata: \(message)\n\n")
            }
        }
        let client = MCPClient(endpoint: StubServer.endpoint, authorizer: StubAuthorizer(), session: server.session)
        let tools = try await client.listTools()
        #expect(tools.map(\.name) == ["list_issues"])
        #expect(server.methods == ["initialize", "notifications/initialized", "tools/list"])
    }

    @Test func refreshesOnceOn401ThenRetries() async throws {
        let server = StubServer { request, body in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer t2" else { return .status(401) }
            if body["method"] == "notifications/initialized" { return .accepted }
            return .json(["jsonrpc": "2.0", "id": body["id"]!, "result": ["content": []]])
        }
        let authorizer = StubAuthorizer()
        let client = MCPClient(endpoint: StubServer.endpoint, authorizer: authorizer, session: server.session)
        _ = try await client.callTool("get_issue", arguments: ["id": "ENG-1"])
        #expect(await authorizer.refreshes == 1)
    }

    @Test func persistent401SurfacesUnauthorized() async {
        let server = StubServer { _, _ in .status(401) }
        let client = MCPClient(endpoint: StubServer.endpoint, authorizer: StubAuthorizer(), session: server.session)
        await #expect(throws: MCPError.unauthorized) { try await client.listTools() }
    }
}

// MARK: - Stubs

actor StubAuthorizer: MCPAuthorizing {
    private var token = "t1"
    private(set) var refreshes = 0

    func accessToken() -> String { token }

    func refreshAccessToken(rejected: String) throws -> String {
        refreshes += 1
        guard refreshes == 1 else { throw MCPError.unauthorized }
        token = "t2"
        return token
    }
}

final class StubServer: @unchecked Sendable {
    enum Reply {
        case json(JSONValue, headers: [String: String] = [:])
        case sse(String)
        case accepted
        case status(Int)
    }

    static let endpoint = URL(string: "https://stub.test/mcp")!
    nonisolated(unsafe) static var current: StubServer?

    let handler: (URLRequest, JSONValue) -> Reply
    private let lock = NSLock()
    private var _methods: [String] = []
    var methods: [String] { lock.withLock { _methods } }
    let session: URLSession

    init(handler: @escaping (URLRequest, JSONValue) -> Reply) {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        Self.current = self
    }

    func respond(to request: URLRequest) -> (HTTPURLResponse, Data) {
        let body = (request.httpBody ?? request.httpBodyStream.map(Self.read)).flatMap { try? JSONValue(data: $0) } ?? .null
        if let method = body["method"]?.stringValue { lock.withLock { _methods.append(method) } }
        let (status, headers, data): (Int, [String: String], Data)
        switch handler(request, body) {
        case .json(let value, let extra):
            (status, headers, data) = (200, extra.merging(["Content-Type": "application/json"]) { a, _ in a },
                                       try! value.encoded())
        case .sse(let text):
            (status, headers, data) = (200, ["Content-Type": "text/event-stream"], Data(text.utf8))
        case .accepted:
            (status, headers, data) = (202, [:], Data())
        case .status(let code):
            (status, headers, data) = (code, [:], Data())
        }
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = StubServer.current else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (response, data) = server.respond(to: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
