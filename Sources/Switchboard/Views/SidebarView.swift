import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(LinearAccount.self) private var linear
    @Environment(GitHubAccount.self) private var github
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.terminalPalette) private var palette
    @State private var search = TicketSearchModel()

    var body: some View {
        let actions = TicketActions(store: store, settings: settings, linear: linear, github: github)
        let fonts = SessionListFonts(settings.sessionListTextSize, fontName: settings.terminalAppearance.fontName)
        let theme = settings.terminalTheme
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SearchHeaderView(search: search) {
                    Task { if await actions.submit(search) { search.clear() } }
                }
                if search.input != .empty {
                    SearchResultsView(search: search, actions: actions)
                }
            }
            .padding(10)
            SessionListControls()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Divider()
            SessionListView(actions: actions)
            UpdateBanner()
        }
        .font(fonts.title)
        .environment(\.sessionListFonts, fonts)
        // The terminal's colors: its text, its dim grey for secondary text,
        // its background, and light or dark to suit that background.
        .foregroundStyle(palette.foreground, palette.dim, palette.dim.opacity(0.7))
        .background(palette.background)
        .environment(\.colorScheme, theme.background == nil ? colorScheme : (theme.isDark ? .dark : .light))
        .task(id: SearchKey(query: search.query, connected: linear.isConnected)) {
            await search.search(using: linear.isConnected ? linear.service : nil)
        }
    }

    private struct SearchKey: Equatable {
        var query: String
        var connected: Bool
    }
}
