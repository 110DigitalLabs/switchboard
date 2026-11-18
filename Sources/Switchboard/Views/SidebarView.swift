import SwiftUI

struct SidebarView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(LinearAccount.self) private var linear
    @Environment(GitHubAccount.self) private var github
    @State private var search = TicketSearchModel()

    var body: some View {
        let actions = TicketActions(store: store, settings: settings, linear: linear, github: github)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SearchHeaderView(search: search) {
                    Task { if await actions.submit(search) { search.clear() } }
                }
                if search.input == .empty {
                    AssignedTicketsView(actions: actions)
                } else {
                    SearchResultsView(search: search, actions: actions)
                }
            }
            .padding(10)
            SessionListControls()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Divider()
            SessionListView()
        }
        .task(id: SearchKey(query: search.query, connected: linear.isConnected)) {
            await search.search(using: linear.isConnected ? linear.service : nil)
        }
    }

    private struct SearchKey: Equatable {
        var query: String
        var connected: Bool
    }
}
