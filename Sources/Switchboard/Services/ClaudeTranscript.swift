import Foundation

/// Reads a Claude Code conversation's name from its transcript JSONL. Claude
/// appends `{"type":"custom-title","customTitle":…}` for `/rename` and `--name`,
/// and `{"type":"ai-title","aiTitle":…}` for its generated title. The latest
/// custom title wins, then the latest generated one.
enum ClaudeTranscript {
    static func title(fromTranscriptAt path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return title(from: data)
    }

    static func title(from data: Data) -> String? {
        var custom: String?
        var generated: String?
        let customMarker = Data(#""type":"custom-title""#.utf8)
        let aiMarker = Data(#""type":"ai-title""#.utf8)
        for line in data.split(separator: UInt8(ascii: "\n")) {
            let isCustom = line.range(of: customMarker) != nil
            guard isCustom || line.range(of: aiMarker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            if isCustom, let value = nonEmpty(object["customTitle"]) {
                custom = value
            } else if let value = nonEmpty(object["aiTitle"]) {
                generated = value
            }
        }
        return custom ?? generated
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
