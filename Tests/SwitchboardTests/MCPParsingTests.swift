import Foundation
import Testing
@testable import Switchboard

struct MCPParsingTests {
    @Test func parsesJSONResponse() throws {
        let body = #"{"jsonrpc":"2.0","id":3,"result":{"tools":[{"name":"get_issue","inputSchema":{"type":"object","properties":{"id":{"type":"string"}}}}]}}"#
        let result = try MCPResponseParser.parseJSON(Data(body.utf8), id: 3)
        let tool = try #require(result["tools"]?.arrayValue?.first.flatMap(MCPTool.init(json:)))
        #expect(tool.name == "get_issue")
        #expect(tool.argumentNames == ["id"])
    }

    @Test func picksMatchingResponseFromBatch() throws {
        let body = #"[{"jsonrpc":"2.0","method":"notifications/message","params":{}},{"jsonrpc":"2.0","id":1,"result":{"a":1}},{"jsonrpc":"2.0","id":2,"result":{"b":2}}]"#
        #expect(try MCPResponseParser.parseJSON(Data(body.utf8), id: 2) == ["b": 2])
    }

    @Test func surfacesRPCErrors() {
        let body = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Unknown tool"}}"#
        #expect(throws: MCPError.rpc(code: -32602, message: "Unknown tool")) {
            try MCPResponseParser.parseJSON(Data(body.utf8), id: 1)
        }
    }

    @Test func parsesEventStreamSkippingNotifications() throws {
        let stream = """
        : keep-alive\r
        event: message\r
        data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\r
        \r
        id: 7\r
        event: message\r
        data: {"jsonrpc":"2.0","id":4,\r
        data:  "result":{"content":[{"type":"text","text":"[]"}]}}\r
        \r

        """
        let result = try MCPResponseParser.parseEventStream(Data(stream.utf8), id: 4)
        #expect(MCPToolResult(json: result).text == "[]")
    }

    @Test func eventStreamWithoutTrailingBlankLineStillParses() throws {
        let stream = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"
        #expect(try MCPResponseParser.parseEventStream(Data(stream.utf8), id: 1) == .object([:]))
    }

    @Test func eventStreamWithoutResponseThrows() {
        #expect(throws: MCPError.noResponse) {
            try MCPResponseParser.parseEventStream(Data("event: ping\ndata: {}\n\n".utf8), id: 1)
        }
    }

    @Test func sseParserHandlesSplitChunks() {
        var parser = SSEParser()
        #expect(parser.feed(Data("data: hel".utf8)).isEmpty)
        #expect(parser.feed(Data("lo\n".utf8)).isEmpty)
        #expect(parser.feed(Data("\n".utf8)) == [SSEParser.Event(type: "message", data: "hello", id: nil)])
    }

    @Test func toolResultPrefersStructuredContentThenText() {
        let structured = MCPToolResult(json: ["content": [["type": "text", "text": "ignored"]],
                                              "structuredContent": ["a": 1]])
        #expect(structured.json == ["a": 1])
        let text = MCPToolResult(json: ["content": [["type": "text", "text": #"{"b":2}"#]], "isError": false])
        #expect(text.json == ["b": 2])
        #expect(!text.isError)
        let plain = MCPToolResult(json: ["content": [["type": "text", "text": "Entity not found"]], "isError": true])
        #expect(plain.json == nil)
        #expect(plain.isError)
    }
}
