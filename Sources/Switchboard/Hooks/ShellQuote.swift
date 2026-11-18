import Foundation

enum ShellQuote {
    /// Single-quotes a word for POSIX shells: `a b'c` becomes `'a b'\''c'`.
    static func quote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Leaves words made only of shell-safe characters (such as UUIDs) bare.
    static func quoteIfNeeded(_ word: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/@")
        let isSafe = !word.isEmpty && word.unicodeScalars.allSatisfy(safe.contains)
        return isSafe ? word : quote(word)
    }
}
