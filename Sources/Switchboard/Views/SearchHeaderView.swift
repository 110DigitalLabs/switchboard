import SwiftUI

/// Placeholder for the stage 4 ticket / PR search and repo dropdown.
struct SearchHeaderView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            TextField("Search tickets or PR URLs", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Menu("No repo") {}
                .fixedSize()
                .disabled(true)
            Button {
                store.isPickerPresented = true
            } label: {
                Image(systemName: "plus")
            }
            .help("New session (⌘N)")
        }
    }
}
