import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            ForEach(store.layout.sections) { section in
                Section(isExpanded: expansion(section.id)) {
                    ForEach(section.items) { item in
                        switch item {
                        case .session(let entry):
                            row(entry)
                        case .ticket(let group):
                            DisclosureGroup(isExpanded: expansion(group.id)) {
                                ForEach(group.entries) { row($0) }
                            } label: {
                                TicketGroupRowView(group: group)
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                }
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

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { !store.isCollapsed(key) },
                set: { store.setCollapsed(key, !$0) })
    }

    private func row(_ entry: SessionListLayout.Entry) -> some View {
        SessionRowView(session: entry.session, ticketLabel: entry.ticketLabel,
                       handoverProgress: store.handoverProgress[entry.session.id])
            .tag(entry.session.id)
            .contextMenu {
                Button("Restart Shell") { store.restartShell(entry.session.id) }
                    .disabled(entry.session.workingState != .exited)
                if entry.session.kind == .folder || entry.session.kind == .temp {
                    Button("Move to Worktree…") { store.handoverRequestID = entry.session.id }
                        .disabled(!entry.session.canMoveToWorktree
                                  || store.handoverProgress[entry.session.id] != nil)
                }
                Divider()
                Button("Close Session") { store.close(entry.session.id) }
            }
    }
}
