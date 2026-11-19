import SwiftUI

/// The sidebar's fonts: the terminal's typeface at the session list's sizes,
/// so the sidebar reads like the terminal beside it.
struct SessionListFonts {
    var title: Font
    var detail: Font
    var detailMonospaced: Font

    init(_ size: SessionListTextSize, fontName: String? = nil) {
        title = Self.font(fontName, size: size.titleSize)
        detail = Self.font(fontName, size: size.detailSize)
        detailMonospaced = detail
    }

    /// A PostScript name that no longer resolves falls back to SF Mono, as
    /// the terminal does.
    private static func font(_ name: String?, size: Double) -> Font {
        if let name, NSFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
        return .system(size: size, design: .monospaced)
    }
}

extension EnvironmentValues {
    @Entry var sessionListFonts = SessionListFonts(.small)
}
