import SwiftUI

struct TerminalPane: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        if let terminal = store.selectedTerminal {
            TerminalHostView(terminal: terminal)
        } else {
            ContentUnavailableView {
                Label("No Session Selected", systemImage: "terminal")
            } description: {
                Text("Select a session, or press ⌘N to start one.")
            }
        }
    }
}
