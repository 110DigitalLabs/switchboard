import Foundation

/// A tool the server advertises in `tools/list`.
struct MCPTool: Hashable, Sendable {
    let name: String
    let description: String?
    let inputSchema: JSONValue

    /// Argument names from the input schema's `properties`.
    var argumentNames: Set<String> {
        Set(inputSchema["properties"]?.objectValue?.keys ?? [:].keys)
    }

    init(name: String, description: String? = nil, inputSchema: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    init?(json: JSONValue) {
        guard let name = json["name"]?.nonEmptyString else { return nil }
        self.init(name: name, description: json["description"]?.stringValue,
                  inputSchema: json["inputSchema"] ?? .object([:]))
    }
}

/// The result of `tools/call`.
struct MCPToolResult: Hashable, Sendable {
    let content: [JSONValue]
    let structuredContent: JSONValue?
    let isError: Bool

    init(content: [JSONValue], structuredContent: JSONValue? = nil, isError: Bool = false) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    init(json: JSONValue) {
        content = json["content"]?.arrayValue ?? []
        structuredContent = json["structuredContent"]
        isError = json["isError"] == .bool(true)
    }

    /// The text blocks, joined.
    var text: String {
        content.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
    }

    /// The result as JSON: structured content when present, otherwise the
    /// text content parsed as JSON. Several text blocks that each hold
    /// JSON become an array.
    var json: JSONValue? {
        if let structuredContent, structuredContent != .null { return structuredContent }
        let blocks = content.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }
        let parsed = blocks.compactMap { try? JSONValue(data: Data($0.utf8)) }
        if parsed.isEmpty { return nil }
        return parsed.count == 1 ? parsed[0] : .array(parsed)
    }
}
