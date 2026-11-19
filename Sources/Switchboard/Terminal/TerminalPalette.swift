import SwiftUI

/// The terminal theme's colors as SwiftUI colors, so the sidebar draws with
/// exactly what the terminal beside it shows: the same background and text,
/// the same 16 ANSI colors a status line script picks from.
struct TerminalPalette {
    var background: Color
    var foreground: Color
    /// ANSI 0–15 in theme order.
    var ansi: [Color]

    init(theme: TerminalTheme) {
        background = Color(nsColor: theme.background?.nsColor ?? .textBackgroundColor)
        foreground = Color(nsColor: theme.foreground?.nsColor ?? .textColor)
        let colors = theme.ansi.map { Color(nsColor: $0.nsColor) }
        ansi = colors.count == 16 ? colors : TerminalTheme.system.ansi.map { Color(nsColor: $0.nsColor) }
    }

    var red: Color { ansi[1] }
    var green: Color { ansi[2] }
    var yellow: Color { ansi[3] }
    var blue: Color { ansi[4] }
    var magenta: Color { ansi[5] }
    var cyan: Color { ansi[6] }
    /// Bright black: what `\e[90m` dim text is drawn in.
    var dim: Color { ansi[8] }

    /// One of the 256 xterm colors: 0–15 from the theme, then the 6×6×6
    /// cube and the grey ramp.
    func xterm(_ index: Int) -> Color? {
        switch index {
        case 0..<16:
            return ansi[index]
        case 16..<232:
            let value = index - 16
            let levels = [0, 95, 135, 175, 215, 255].map { Double($0) / 255 }
            return Color(.sRGB, red: levels[value / 36], green: levels[(value / 6) % 6], blue: levels[value % 6])
        case 232..<256:
            let level = Double(8 + (index - 232) * 10) / 255
            return Color(.sRGB, red: level, green: level, blue: level)
        default:
            return nil
        }
    }
}

extension EnvironmentValues {
    @Entry var terminalPalette = TerminalPalette(theme: .system)
}
