import Foundation

/// Finds Linear issue IDs mentioned in free text, such as a prompt.
enum TicketMentions {
    /// IDs whose team key is in `validTeamKeys`, upper-cased, in order of
    /// first appearance. Unknown keys never match, so "UTF-8" or "GPT-4"
    /// are ignored unless a team really uses that key.
    static func find(in text: String, validTeamKeys: Set<String>) -> [String] {
        guard !validTeamKeys.isEmpty else { return [] }
        let keys = Set(validTeamKeys.map { $0.uppercased() })
        var seen = Set<String>()
        var found: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let numberRange = Range(match.range(at: 2), in: text) else { continue }
            let key = text[keyRange].uppercased()
            guard keys.contains(key) else { continue }
            let id = "\(key)-\(text[numberRange])"
            if seen.insert(id).inserted { found.append(id) }
        }
        return found
    }

    /// A key and number not glued to surrounding letters or digits.
    private static let pattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_-])([A-Za-z][A-Za-z0-9]+)-([0-9]+)(?![A-Za-z0-9_])")
}
