import Foundation

/// What a finished utterance asks for. Anything that is not a recognised
/// command is dictation for the selected session.
enum VoiceCommand: Equatable {
    /// "Switchboard 2": select the session at that 1-based sidebar position
    /// (the same numbering as Cmd-1…9), then type `then` into it, if any.
    case select(position: Int, then: String?)
    /// "Send" on its own: press Return in the selected session.
    case submit
    /// Text to type into the selected session, without pressing Return.
    case dictate(String)

    init?(transcript: String) {
        let words = Self.words(in: transcript)
        guard !words.isEmpty else { return nil }

        if Self.submitPhrases.contains(words) {
            self = .submit
            return
        }

        if let afterName = Self.droppingWakeWord(words), let first = afterName.first {
            let rest = Array(afterName.dropFirst())
            // "to", "for" and friends only count as numbers when nothing
            // follows, so "switchboard to run tests" is never read as 2.
            if let position = Self.numbers[first] ?? (rest.isEmpty ? Self.homophones[first] : nil),
               position >= 1 {
                let then = rest.isEmpty ? nil : Self.originalTail(of: transcript, droppingWords: words.count - rest.count)
                self = .select(position: position, then: then)
                return
            }
        }

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self = .dictate(text)
    }

    private static let submitPhrases: Set<[String]> = [
        ["send"], ["send", "it"], ["submit"], ["enter"], ["press", "enter"], ["press", "return"],
    ]

    /// Matches "switchboard", "switch board" and "switchboards" at the start.
    private static func droppingWakeWord(_ words: [String]) -> [String]? {
        if words.first == "switchboard" || words.first == "switchboards" { return Array(words.dropFirst()) }
        if words.count >= 2, words[0] == "switch", words[1] == "board" || words[1] == "boards" {
            return Array(words.dropFirst(2))
        }
        return nil
    }

    private static let numbers: [String: Int] = {
        var table: [String: Int] = [:]
        let names = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                     "eighteen", "nineteen", "twenty"]
        for (index, name) in names.enumerated() {
            table[name] = index + 1
            table[String(index + 1)] = index + 1
        }
        table["first"] = 1; table["second"] = 2; table["third"] = 3
        return table
    }()

    private static let homophones: [String: Int] = [
        "won": 1, "to": 2, "too": 2, "tu": 2, "tree": 3, "for": 4, "fore": 4, "sex": 6, "ate": 8, "nein": 9,
    ]

    /// Lowercased words with surrounding punctuation stripped ("Switchboard,"
    /// and "2." become "switchboard" and "2"). Hyphens split words.
    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    /// The transcript after its first `count` words, with original casing.
    private static func originalTail(of transcript: String, droppingWords count: Int) -> String? {
        var remaining = Substring(transcript)
        var dropped = 0
        while dropped < count {
            remaining = remaining.drop(while: { $0.isWhitespace || $0 == "-" })
            let word = remaining.prefix(while: { !$0.isWhitespace && $0 != "-" })
            if !word.trimmingCharacters(in: .punctuationCharacters).isEmpty { dropped += 1 }
            remaining = remaining.dropFirst(word.count)
        }
        let tail = remaining.drop(while: { $0.isWhitespace || $0.isPunctuation })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }
}
