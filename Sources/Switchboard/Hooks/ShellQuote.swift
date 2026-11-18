import Foundation

enum ShellQuote {
    /// Single-quotes a word for POSIX shells: `a b'c` becomes `'a b'\''c'`.
    static func quote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
