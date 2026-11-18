import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            if !store.mainSessions.isEmpty {
                Section("Sessions") { rows(store.mainSessions) }
            }
            if !store.scratchSessions.isEmpty {
                Section("Scratch") { rows(store.scratchSessions) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.sessions.isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rows(_ sessions: [Session]) -> some View {
        ForEach(sessions) { session in
            SessionRowView(session: session)
                .tag(session.id)
                .contextMenu {
                    Button("Restart Shell") { store.restartShell(session.id) }
                        .disabled(session.workingState != .exited)
                    Divider()
                    Button("Close Session") { store.close(session.id) }
                }
        }
    }
}
