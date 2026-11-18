import Foundation

/// Makes external text (ticket titles, PR titles, URLs) safe to type into a
/// terminal as a draft: one line, no control characters, no escapes.
enum TypedText {
    /// Strips ANSI escape sequences, then drops every Unicode scalar in the
    /// Cc and Cf categories (CR, LF, ESC, C1 controls such as CSI U+009B,
    /// bidi overrides, zero-width characters), and collapses whitespace runs
    /// to single spaces. A trailing space is kept so the cursor can sit
    /// after the text; leading whitespace is dropped.
    static func sanitize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in withoutEscapeSequences(text).unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control:
                // Tabs and line breaks become spaces so words stay apart.
                if scalar == "\t" || scalar == "\n" || scalar == "\r" { scalars.append(" ") }
            case .format:
                continue
            default:
                scalars.append(scalar.properties.isWhitespace ? " " : scalar)
            }
        }
        var result = ""
        var lastWasSpace = true
        for character in String(scalars) {
            if character == " " {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result
    }

    /// Removes CSI (`ESC [` or U+009B), OSC/DCS/APC/PM/SOS strings (ended by
    /// BEL or ST), and two-character `ESC x` sequences. Leftover lone
    /// controls are dropped by `sanitize`.
    private static func withoutEscapeSequences(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return escapePattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static let escapePattern = try! NSRegularExpression(pattern: [
        // CSI: ESC [ or 8-bit CSI, parameters, intermediates, final byte.
        "(?:\\u001B\\[|\\u009B)[\\u0030-\\u003F]*[\\u0020-\\u002F]*[\\u0040-\\u007E]?",
        // OSC, DCS, SOS, PM, APC strings up to BEL or ST (or end of text).
        "(?:\\u001B[\\]P^_X]|[\\u009D\\u0090\\u0098\\u009E\\u009F])[^\\u0007\\u001B\\u009C]*(?:\\u0007|\\u001B\\\\|\\u009C)?",
        // Any other two-character escape.
        "\\u001B[\\u0020-\\u007E]?",
    ].joined(separator: "|"))
}
