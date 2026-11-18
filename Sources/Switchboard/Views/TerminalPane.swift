import SwiftUI

struct TerminalPane: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        if let terminal = store.selectedTerminal {
            VStack(spacing: 0) {
                TerminalHostView(terminal: terminal)
                if let session = store.sessions.first(where: { $0.id == store.selectedID }) {
                    Divider()
                    SessionStatusBar(session: session)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Session Selected", systemImage: "terminal")
            } description: {
                Text("Select a session, or press ⌘N to start one.")
            }
        }
    }
}
