import Foundation

enum StatusLineText {
    /// Strips terminal escape sequences and control characters and joins the
    /// non-empty lines into one, for display in a row.
    static func singleLine(_ raw: String) -> String {
        stripANSI(raw)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    static func stripANSI(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            if scalar == "\u{1B}" {
                skipEscape(&scalars)
            } else if scalar == "\u{9B}" {
                skipCSI(&scalars)
            } else if scalar == "\n" || scalar == "\t" {
                output.append(scalar == "\t" ? " " : scalar)
            } else if scalar.properties.generalCategory != .control {
                output.append(scalar)
            }
        }
        return String(output)
    }

    private static func skipEscape(_ scalars: inout String.UnicodeScalarView.Iterator) {
        guard let next = scalars.next() else { return }
        switch next {
        case "[":
            skipCSI(&scalars)
        case "]", "P", "X", "^", "_":
            // OSC / DCS / SOS / PM / APC: until BEL or ESC \.
            while let s = scalars.next() {
                if s == "\u{07}" { return }
                if s == "\u{1B}" { _ = scalars.next(); return }
            }
        case "(", ")", "*", "+", "#", "%":
            _ = scalars.next() // charset designation takes one more byte
        default:
            return // two-byte escape such as ESC 7
        }
    }

    /// Parameters and intermediates, ended by a final byte in 0x40...0x7E.
    private static func skipCSI(_ scalars: inout String.UnicodeScalarView.Iterator) {
        while let s = scalars.next() {
            if (0x40...0x7E).contains(s.value) { return }
        }
    }
}
