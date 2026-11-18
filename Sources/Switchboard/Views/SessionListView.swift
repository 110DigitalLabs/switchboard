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
        .modifier(CloseFolderDialog())
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

    @ViewBuilder
    private func row(_ entry: SessionListLayout.Entry) -> some View {
        let session = entry.session
        if let closedAt = session.closedAt {
            SessionRowView(session: session, ticketLabel: entry.ticketLabel,
                           keptNote: TempCleanupPolicy.keptNote(closedAt: closedAt, now: Date(),
                                                                days: store.settings.tempCleanupDays))
                .opacity(0.5)
                .contextMenu {
                    Button("Reopen") { store.reopenKept(session.id) }
                    Divider()
                    Button("Delete Now", role: .destructive) { store.deleteKept(session.id) }
                }
        } else {
            SessionRowView(session: session, ticketLabel: entry.ticketLabel,
                           handoverProgress: store.handoverProgress[session.id])
                .tag(session.id)
                .contextMenu {
                    Button("Restart Shell") { store.restartShell(session.id) }
                        .disabled(session.workingState != .exited)
                    if session.kind == .folder || session.kind == .temp {
                        Button("Move to Worktree…") { store.handoverRequestID = session.id }
                            .disabled(!session.canMoveToWorktree || store.handoverProgress[session.id] != nil)
                    }
                    Divider()
                    Button("Close Session") { store.requestClose(session.id) }
                }
        }
    }
}

/// "Delete folder <path>?" when closing a temp or scratch row.
private struct CloseFolderDialog: ViewModifier {
    @Environment(SessionStore.self) private var store

    func body(content: Content) -> some View {
        let session = store.closeRequestID.flatMap { id in store.sessions.first { $0.id == id } }
        content.alert(
            "Delete folder \(((session?.folderPath ?? "") as NSString).abbreviatingWithTildeInPath)?",
            isPresented: Binding(get: { session != nil }, set: { if !$0 { store.closeRequestID = nil } }),
            presenting: session
        ) { session in
            Button("Delete", role: .destructive) { store.closeDeletingFolder(session.id) }
            Button("Keep") { store.closeKeepingFolder(session.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Delete moves it to the Trash. Keep leaves it in the Temp section, deleted after \(store.settings.tempCleanupDays) days.")
        }
    }
}
