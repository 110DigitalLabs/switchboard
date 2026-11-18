import SwiftUI

/// Fonts for session list rows, sized by the "Session list text" setting.
struct SessionListFonts {
    var title: Font
    var detail: Font
    var detailMonospaced: Font

    init(_ size: SessionListTextSize) {
        title = .system(size: size.titleSize)
        detail = .system(size: size.detailSize)
        detailMonospaced = .system(size: size.detailSize).monospaced()
    }
}

extension EnvironmentValues {
    @Entry var sessionListFonts = SessionListFonts(.small)
}
