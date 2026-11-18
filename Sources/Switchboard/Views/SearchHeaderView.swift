import SwiftUI

/// The search box, the repo dropdown and the "+" button.
struct SearchHeaderView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LinearAccount.self) private var linear
    @Bindable var search: TicketSearchModel
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Ticket ID, Linear URL or search", text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSubmit)
                    .disabled(!linear.isConnected)
                    .onExitCommand { search.clear() }
                RepoDropdown()
                Button {
                    store.isPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New session (⌘N)")
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
