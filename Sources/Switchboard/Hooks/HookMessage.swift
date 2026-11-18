import Foundation

/// One message from the hook helper; see `HookScript` for the wire format.
struct HookMessage: Equatable, Sendable {
    var agent: String
    var event: String
    var rowID: UUID
    var payload: Data
    /// Text after the payload, e.g. the user's rendered status line.
    var trailingText: String

    init(agent: String, event: String, rowID: UUID, payload: Data, trailingText: String = "") {
        self.agent = agent
        self.event = event
        self.rowID = rowID
        self.payload = payload
        self.trailingText = trailingText
    }

    init?(data: Data) {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = String(data: data[data.startIndex..<newline], encoding: .utf8)
        else { return nil }
        let fields = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5, fields[0] == "SWB1",
              let rowID = UUID(uuidString: fields[3]),
              let length = Int(fields[4]), length >= 0
        else { return nil }
        let body = data[data.index(after: newline)...]
        guard body.count >= length else { return nil }
        let split = body.index(body.startIndex, offsetBy: length)
        self.init(agent: fields[1], event: fields[2], rowID: rowID,
                  payload: Data(body[body.startIndex..<split]),
                  trailingText: String(decoding: body[split...], as: UTF8.self))
    }
}
