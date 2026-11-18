import SwiftUI

/// The search box, the repo dropdown and the "+" button.
struct SearchHeaderView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LinearAccount.self) private var linear
    @Environment(AppSettings.self) private var settings
    @Bindable var search: TicketSearchModel
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(linear.isConnected ? "Ticket ID, Linear or PR URL, or search" : "GitHub PR URL",
                          text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSubmit)
                    .onExitCommand { search.clear() }
                RepoDropdown()
                Button {
                    store.newSession()
                } label: {
                    Image(systemName: "plus")
                }
                .help(settings.ticketRepoPath == nil
                      ? "New session (⌘N)"
                      : "New session in the selected repo (⌘N); ⇧⌘N to choose")
            }
            if !linear.isConnected {
                LinearSignInHint()
            }
        }
    }
}

/// Shown wherever ticket features are greyed out.
struct LinearSignInHint: View {
    @Environment(LinearAccount.self) private var linear

    var body: some View {
        HStack(spacing: 4) {
            Text(linear.status == .offline ? "Linear is offline." : "Sign in to Linear in Settings.")
            SettingsLink { Text("Open Settings") }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
