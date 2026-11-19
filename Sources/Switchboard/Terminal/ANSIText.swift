import SwiftUI

/// Turns a status line's terminal output into styled text: SGR colors from
/// the terminal palette, bold, faint, italic and underline. Other escape
/// sequences (cursor moves, OSC 8 links, titles) are dropped, their text kept.
enum ANSIText {
    /// The first line with visible text, styled.
    static func firstLine(of output: String, palette: TerminalPalette) -> AttributedString? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let line = lines.first(where: { !strip(String($0)).trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        return attributed(String(line), palette: palette)
    }

    /// `text` without any escape sequences.
    static func strip(_ text: String) -> String {
        String(String.UnicodeScalarView(segments(text).flatMap { segment -> [Unicode.Scalar] in
            if case .text(let scalars) = segment { return scalars }
            return []
        }))
    }

    static func attributed(_ text: String, palette: TerminalPalette) -> AttributedString {
        var result = AttributedString()
        var style = Style()
        for segment in segments(text) {
            switch segment {
            case .text(let scalars):
                var run = AttributedString(String(String.UnicodeScalarView(scalars)))
                style.apply(to: &run, palette: palette)
                result += run
            case .sgr(let codes):
                style.update(with: codes)
            }
        }
        return result
    }

    // MARK: Parsing

    enum Segment: Equatable {
        case text([Unicode.Scalar])
        case sgr([Int])
    }

    static func segments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var pending: [Unicode.Scalar] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0

        func flush() {
            if !pending.isEmpty { segments.append(.text(pending)) }
            pending = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\u{1B}", index + 1 < scalars.count else {
                if scalar.value >= 0x20 || scalar == "\t" { pending.append(scalar) }
                index += 1
                continue
            }
            let kind = scalars[index + 1]
            index += 2
            if kind == "[" {
                // CSI: parameters, then a final byte in @...~.
                var parameters = ""
                while index < scalars.count, !(0x40...0x7E).contains(scalars[index].value) {
                    parameters.unicodeScalars.append(scalars[index])
                    index += 1
                }
                let final = index < scalars.count ? scalars[index] : nil
                index += 1
                if final == "m" {
                    flush()
                    let codes = parameters.split(separator: ";", omittingEmptySubsequences: false)
                        .map { Int($0) ?? 0 }
                    segments.append(.sgr(codes.isEmpty ? [0] : codes))
                }
            } else if kind == "]" {
                // OSC: runs to BEL or ESC \.
                while index < scalars.count {
                    if scalars[index] == "\u{07}" { index += 1; break }
                    if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "\\" {
                        index += 2
                        break
                    }
                    index += 1
                }
            }
        }
        flush()
        return segments
    }

    private enum ColorRef: Equatable {
        case xterm(Int)
        case rgb(Double, Double, Double)
    }

    private struct Style {
        var color: ColorRef?
        var bold = false
        var faint = false
        var italic = false
        var underline = false

        mutating func update(with codes: [Int]) {
            var index = 0
            while index < codes.count {
                let code = codes[index]
                switch code {
                case 0: self = Style()
                case 1: bold = true
                case 2: faint = true
                case 3: italic = true
                case 4: underline = true
                case 22: bold = false; faint = false
                case 23: italic = false
                case 24: underline = false
                case 30...37: color = .xterm(code - 30)
                case 90...97: color = .xterm(code - 90 + 8)
                case 39: color = nil
                case 38, 48:
                    // Extended color; background ones are skipped.
                    var parsed: ColorRef?
                    if index + 2 < codes.count, codes[index + 1] == 5 {
                        parsed = .xterm(codes[index + 2])
                        index += 2
                    } else if index + 4 < codes.count, codes[index + 1] == 2 {
                        parsed = .rgb(Double(codes[index + 2]) / 255, Double(codes[index + 3]) / 255,
                                      Double(codes[index + 4]) / 255)
                        index += 4
                    }
                    if code == 38, let parsed { color = parsed }
                default: break
                }
                index += 1
            }
        }

        func apply(to run: inout AttributedString, palette: TerminalPalette) {
            switch color {
            case .xterm(let index):
                run.foregroundColor = palette.xterm(index)
            case .rgb(let red, let green, let blue):
                run.foregroundColor = Color(.sRGB, red: red, green: green, blue: blue)
            case nil:
                break
            }
            if faint { run.foregroundColor = (run.foregroundColor ?? palette.foreground).opacity(0.6) }
            if bold { run.inlinePresentationIntent = .stronglyEmphasized }
            if italic { run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.emphasized) }
            if underline { run.underlineStyle = .single }
        }
    }
}
