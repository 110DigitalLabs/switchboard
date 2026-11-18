import Foundation
import Testing
@testable import Switchboard

struct HookMessageTests {
    static let row = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func parsesHeaderPayloadAndTrailingText() throws {
        let payload = #"{"session_id":"s1"}"#
        let wire = "SWB1\tclaude\tstatusline\t\(Self.row.uuidString)\t\(payload.utf8.count)\n\(payload)\u{1B}[1mOpus\u{1B}[0m\n"
        let message = try #require(HookMessage(data: Data(wire.utf8)))
        #expect(message.agent == "claude")
        #expect(message.event == "statusline")
        #expect(message.rowID == Self.row)
        #expect(String(decoding: message.payload, as: UTF8.self) == payload)
        #expect(message.trailingText == "\u{1B}[1mOpus\u{1B}[0m\n")
    }

    @Test func payloadLengthCountsBytesNotCharacters() throws {
        let payload = #"{"session_name":"Café ✓"}"#
        let wire = "SWB1\tclaude\tstatusline\t\(Self.row.uuidString)\t\(payload.utf8.count)\n\(payload)tail"
        let message = try #require(HookMessage(data: Data(wire.utf8)))
        #expect(String(decoding: message.payload, as: UTF8.self) == payload)
        #expect(message.trailingText == "tail")
    }

    @Test(arguments: [
        "",
        "SWB1\tclaude\tStop\tnot-a-uuid\t2\n{}",
        "SWB2\tclaude\tStop\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t2\n{}",
        "SWB1\tclaude\tStop\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t99\n{}",
        "SWB1\tclaude\tStop\n{}",
    ])
    func rejectsMalformedMessages(wire: String) {
        #expect(HookMessage(data: Data(wire.utf8)) == nil)
    }
}
