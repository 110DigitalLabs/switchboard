import AppKit
import SwiftTerm

/// How every terminal looks: font, size, cursor and color theme.
struct TerminalAppearance: Codable, Hashable, Sendable {
    enum CursorShape: String, Codable, CaseIterable, Identifiable, Sendable {
        case block, bar, underline

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// A PostScript name; nil is the system monospaced font (SF Mono).
    var fontName: String?
    var fontSize: Double = Self.defaultFontSize
    var themeID: String = TerminalTheme.systemID
    var cursorShape: CursorShape = .block
    var cursorBlinks: Bool = true

    static let defaultFontSize: Double = 13
    static let fontSizes: ClosedRange<Double> = 8...36

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = Self.clamped(try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaultFontSize)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? TerminalTheme.systemID
        cursorShape = (try? c.decodeIfPresent(CursorShape.self, forKey: .cursorShape)) ?? .block
        cursorBlinks = try c.decodeIfPresent(Bool.self, forKey: .cursorBlinks) ?? true
    }

    static func clamped(_ size: Double) -> Double {
        min(max(size.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }

    /// One point bigger or smaller, within `fontSizes`.
    func resized(by step: Double) -> TerminalAppearance {
        var copy = self
        copy.fontSize = Self.clamped(fontSize + step)
        return copy
    }

    var font: NSFont {
        let size = CGFloat(fontSize)
        return fontName.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var cursorStyle: CursorStyle {
        switch (cursorShape, cursorBlinks) {
        case (.block, true): .blinkBlock
        case (.block, false): .steadyBlock
        case (.bar, true): .blinkBar
        case (.bar, false): .steadyBar
        case (.underline, true): .blinkUnderline
        case (.underline, false): .steadyUnderline
        }
    }

    @MainActor
    func apply(_ theme: TerminalTheme, to view: TerminalView) {
        view.font = font
        view.nativeForegroundColor = theme.foreground?.nsColor ?? .textColor
        view.nativeBackgroundColor = theme.background?.nsColor ?? .textBackgroundColor
        view.installColors(theme.ansi.map {
            Color(red: UInt16($0.red * 65535), green: UInt16($0.green * 65535), blue: UInt16($0.blue * 65535))
        })
        view.caretColor = theme.cursor?.nsColor ?? .selectedControlColor
        view.selectedTextBackgroundColor = theme.selection?.nsColor ?? .selectedTextBackgroundColor
        view.selectedTextForegroundColor = theme.selection == nil ? .selectedTextColor : theme.foreground?.nsColor
            ?? .textColor
        view.setCursorStyle(cursorStyle)
    }
}

/// Fixed-pitch fonts installed on this Mac, one regular face per family.
enum MonospacedFonts {
    struct Choice: Hashable, Identifiable {
        var postScriptName: String
        var family: String
        var id: String { postScriptName }
    }

    @MainActor static let installed: [Choice] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.compactMap { family in
            let members = manager.availableMembers(ofFontFamily: family) ?? []
            let regular = members.first { ($0[1] as? String) == "Regular" } ?? members.first
            guard let name = regular?[0] as? String, let font = NSFont(name: name, size: 12),
                  font.isFixedPitch, !family.hasPrefix(".") else { return nil }
            return Choice(postScriptName: name, family: family)
        }
    }()
}
