import AppKit

/// A terminal color scheme: text, background, cursor, selection and the 16
/// ANSI colors. The System theme leaves the first four to macOS's text
/// colors, so it follows light and dark mode.
struct TerminalTheme: Codable, Hashable, Identifiable, Sendable {
    struct RGB: Codable, Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    var id: String
    var name: String
    /// Nil for the System theme's dynamic colors.
    var foreground: RGB?
    var background: RGB?
    var cursor: RGB?
    var selection: RGB?
    /// Black, red, green, yellow, blue, magenta, cyan, white, then the
    /// bright eight.
    var ansi: [RGB]

    static let systemID = "system"

    var isDark: Bool {
        guard let background else { return NSApp?.effectiveAppearance.isDark ?? false }
        return 0.299 * background.red + 0.587 * background.green + 0.114 * background.blue < 0.5
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

// MARK: Built-in themes

extension TerminalTheme {
    private static func make(_ id: String, _ name: String, fg: UInt32, bg: UInt32, cursor: UInt32,
                             selection: UInt32, _ ansi: [UInt32]) -> TerminalTheme {
        TerminalTheme(id: id, name: name, foreground: RGB(fg), background: RGB(bg), cursor: RGB(cursor),
                      selection: RGB(selection), ansi: ansi.map(RGB.init))
    }

    /// Terminal.app's palette, which SwiftTerm also starts with.
    static let system = TerminalTheme(id: systemID, name: "System", ansi: [
        0x000000, 0x990000, 0x00A600, 0x999900, 0x0000B2, 0xB200B2, 0x00A6B2, 0xBFBFBF,
        0x666666, 0xE50000, 0x00D900, 0xE5E500, 0x0000FF, 0xE500E5, 0x00E5E5, 0xE5E5E5,
    ].map(RGB.init))

    private static let solarizedANSI: [UInt32] = [
        0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
        0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
    ]

    private static let tangoANSI: [UInt32] = [
        0x2E3436, 0xCC0000, 0x4E9A06, 0xC4A000, 0x3465A4, 0x75507B, 0x06989A, 0xD3D7CF,
        0x555753, 0xEF2929, 0x8AE234, 0xFCE94F, 0x729FCF, 0xAD7FA8, 0x34E2E2, 0xEEEEEC,
    ]

    static let builtIn: [TerminalTheme] = [
        system,
        make("solarized-dark", "Solarized Dark", fg: 0x839496, bg: 0x002B36, cursor: 0x93A1A1,
             selection: 0x073642, solarizedANSI),
        make("solarized-light", "Solarized Light", fg: 0x657B83, bg: 0xFDF6E3, cursor: 0x586E75,
             selection: 0xEEE8D5, solarizedANSI),
        make("dracula", "Dracula", fg: 0xF8F8F2, bg: 0x282A36, cursor: 0xF8F8F2, selection: 0x44475A, [
            0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
            0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
        ]),
        make("nord", "Nord", fg: 0xD8DEE9, bg: 0x2E3440, cursor: 0xD8DEE9, selection: 0x434C5E, [
            0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
            0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
        ]),
        make("gruvbox-dark", "Gruvbox Dark", fg: 0xEBDBB2, bg: 0x282828, cursor: 0xEBDBB2, selection: 0x504945, [
            0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
            0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
        ]),
        make("one-dark", "One Dark", fg: 0xABB2BF, bg: 0x282C34, cursor: 0x528BFF, selection: 0x3E4451, [
            0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
            0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF,
        ]),
        make("tomorrow-night", "Tomorrow Night", fg: 0xC5C8C6, bg: 0x1D1F21, cursor: 0xC5C8C6,
             selection: 0x373B41, [
                0x1D1F21, 0xCC6666, 0xB5BD68, 0xF0C674, 0x81A2BE, 0xB294BB, 0x8ABEB7, 0xC5C8C6,
                0x969896, 0xCC6666, 0xB5BD68, 0xF0C674, 0x81A2BE, 0xB294BB, 0x8ABEB7, 0xFFFFFF,
             ]),
        make("tango-dark", "Tango Dark", fg: 0xD3D7CF, bg: 0x2E3436, cursor: 0xD3D7CF, selection: 0x555753,
             tangoANSI),
        make("tango-light", "Tango Light", fg: 0x2E3436, bg: 0xEEEEEC, cursor: 0x2E3436, selection: 0xD3D7CF,
             tangoANSI),
    ]
}

// MARK: iTerm2 colors

extension TerminalTheme {
    /// An `.itermcolors` file, or the same keys inside an iTerm2 profile:
    /// `Ansi 0 Color` … `Ansi 15 Color`, `Foreground Color`, `Background
    /// Color`, `Cursor Color`, `Selection Color`, each a dictionary of
    /// `Red Component`, `Green Component` and `Blue Component` from 0 to 1.
    /// Nil unless all 16 ANSI colors are present.
    init?(iTermColors plist: [String: Any], id: String, name: String) {
        func color(_ key: String) -> RGB? {
            guard let entry = plist[key] as? [String: Any],
                  let red = (entry["Red Component"] as? NSNumber)?.doubleValue,
                  let green = (entry["Green Component"] as? NSNumber)?.doubleValue,
                  let blue = (entry["Blue Component"] as? NSNumber)?.doubleValue
            else { return nil }
            return RGB(red: red, green: green, blue: blue)
        }
        let ansi = (0..<16).compactMap { color("Ansi \($0) Color") }
        guard ansi.count == 16 else { return nil }
        self.init(id: id, name: name, foreground: color("Foreground Color"), background: color("Background Color"),
                  cursor: color("Cursor Color"), selection: color("Selection Color"), ansi: ansi)
    }

    /// Reads an `.itermcolors` file, named after the file.
    init?(iTermColorsFile url: URL) {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        self.init(iTermColors: plist, id: "imported:\(name)", name: name)
    }
}

/// The font and colors of iTerm2's default profile, read from its
/// preferences (`com.googlecode.iterm2`).
struct ITermProfile: Equatable {
    var name: String
    var fontName: String?
    var fontSize: Double?
    var theme: TerminalTheme?

    static func defaultProfile(defaults: UserDefaults? = UserDefaults(suiteName: "com.googlecode.iterm2")) -> ITermProfile? {
        guard let defaults,
              let profiles = defaults.array(forKey: "New Bookmarks") as? [[String: Any]], !profiles.isEmpty
        else { return nil }
        let guid = defaults.string(forKey: "Default Bookmark Guid")
        let profile = profiles.first { $0["Guid"] as? String == guid } ?? profiles[0]
        return ITermProfile(profile: profile)
    }

    init(name: String, fontName: String?, fontSize: Double?, theme: TerminalTheme?) {
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.theme = theme
    }

    init(profile: [String: Any]) {
        name = profile["Name"] as? String ?? "Default"
        (fontName, fontSize) = Self.font(profile["Normal Font"] as? String)
        theme = TerminalTheme(iTermColors: profile, id: "imported:iterm2-\(name)", name: "iTerm2 – \(name)")
    }

    /// iTerm2 stores fonts as `"<PostScript name> <size>"`, e.g. `"Monaco 12"`.
    static func font(_ value: String?) -> (String?, Double?) {
        guard let value, let space = value.lastIndex(of: " "),
              let size = Double(value[value.index(after: space)...]) else { return (nil, nil) }
        let name = String(value[..<space])
        return (name.isEmpty ? nil : name, size)
    }
}
