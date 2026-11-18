import Foundation

/// Picks the JSON-RPC response out of a Streamable HTTP reply, which is
/// either one JSON message (or a batch) or a server-sent event stream.
enum MCPResponseParser {
    static func isEventStream(contentType: String?) -> Bool {
        contentType?.lowercased().hasPrefix("text/event-stream") ?? false
    }

    static func parseJSON(_ data: Data, id: Int) throws -> JSONValue {
        let message: JSONValue
        do {
            message = try JSONValue(data: data)
        } catch {
            throw MCPError.malformedResponse("body is not JSON")
        }
        let candidates = message.arrayValue ?? [message]
        for candidate in candidates {
            if let result = JSONRPC.result(of: candidate, id: id) { return try result.get() }
        }
        throw MCPError.noResponse
    }

    /// Parses a complete event-stream body. Used for fixtures; the client
    /// reads streams incrementally with `SSEParser`.
    static func parseEventStream(_ data: Data, id: Int) throws -> JSONValue {
        var parser = SSEParser()
        var events = parser.feed(data)
        events += parser.finish()
        for event in events {
            if let result = try result(in: event, id: id) { return result }
        }
        throw MCPError.noResponse
    }

    /// The response to `id` carried by `event`, if any.
    static func result(in event: SSEParser.Event, id: Int) throws -> JSONValue? {
        guard event.type == "message", !event.data.isEmpty,
              let message = try? JSONValue(data: Data(event.data.utf8)) else { return nil }
        for candidate in message.arrayValue ?? [message] {
            if let result = JSONRPC.result(of: candidate, id: id) { return try result.get() }
        }
        return nil
    }
}

/// Incremental parser for the text/event-stream format.
struct SSEParser {
    struct Event: Equatable {
        var type: String
        var data: String
        var id: String?
    }

    private var buffer = Data()
    private var dataLines: [String] = []
    private var eventType: String?
    private var eventID: String?

    /// Feeds raw bytes; returns the events completed by them.
    mutating func feed(_ bytes: Data) -> [Event] {
        buffer.append(bytes)
        var events: [Event] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[buffer.startIndex..<newline]
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = process(line: String(decoding: lineData, as: UTF8.self)) {
                events.append(event)
            }
        }
        return events
    }

    /// Flushes a final event that the stream closed without a blank line.
    mutating func finish() -> [Event] {
        var events: [Event] = []
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            if let event = process(line: line) { events.append(event) }
        }
        if let event = process(line: "") { events.append(event) }
        return events
    }

    private mutating func process(line: String) -> Event? {
        if line.isEmpty {
            defer { dataLines = []; eventType = nil }
            guard !dataLines.isEmpty else { return nil }
            return Event(type: eventType ?? "message", data: dataLines.joined(separator: "\n"), id: eventID)
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "data": dataLines.append(String(value))
        case "event": eventType = String(value)
        case "id": eventID = String(value)
        default: break
        }
        return nil
    }
}
