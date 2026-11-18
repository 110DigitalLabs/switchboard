import Foundation

/// JSON-RPC 2.0 framing for MCP.
enum JSONRPC {
    static func request(id: Int, method: String, params: JSONValue?) -> JSONValue {
        var object: [String: JSONValue] = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method)]
        if let params { object["params"] = params }
        return .object(object)
    }

    static func notification(method: String, params: JSONValue? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method)]
        if let params { object["params"] = params }
        return .object(object)
    }

    /// The result of the response to `id`, or the error it carries.
    /// Returns nil when `message` is not that response (a notification,
    /// a server request, or a response to something else).
    static func result(of message: JSONValue, id: Int) -> Result<JSONValue, MCPError>? {
        guard message["method"] == nil, message["id"]?.intValue == id else { return nil }
        if let error = message["error"] {
            return .failure(.rpc(code: error["code"]?.intValue ?? 0,
                                 message: error["message"]?.stringValue ?? "Unknown error"))
        }
        return .success(message["result"] ?? .null)
    }
}
