import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var resumeRequest: PastConversation?

    static let elsewhereSectionID = "elsewhere"

    var body: some View {
        @Bindable var store = store
        let layout = store.layout
        let shortcuts = layout.shortcutNumbers
        List(selection: $store.selectedID) {
            ForEach(layout.sections) { section in
                Section(isExpanded: expansion(section.id)) {
                    ForEach(section.items) { item in
                        switch item {
                        case .session(let entry):
                            row(entry, shortcuts)
                        case .ticket(let group):
                            DisclosureGroup(isExpanded: expansion(group.id)) {
                                ForEach(group.entries) { row($0, shortcuts) }
                            } label: {
                                TicketGroupRowView(group: group)
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                }
            }
            if !store.elsewhere.isEmpty {
                Section(isExpanded: expansion(Self.elsewhereSectionID)) {
                    ForEach(store.elsewhere) { conversation in
                        ElsewhereRowView(conversation: conversation)
                            .contentShape(Rectangle())
                            .onTapGesture { resumeRequest = conversation }
                            .contextMenu {
                                Button("Resume Here…") { resumeRequest = conversation }
                            }
                    }
                } header: {
                    Text("Running Elsewhere")
                        .help("Claude Code and Codex sessions open in other terminals. Click one to move it here.")
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.sessionListFonts, SessionListFonts(settings.sessionListTextSize))
        .modifier(CloseFolderDialog())
        .confirmationDialog("Resume “\(resumeRequest?.displayTitle ?? "")” here?",
                            isPresented: Binding(get: { resumeRequest != nil },
                                                 set: { if !$0 { resumeRequest = nil } }),
                            presenting: resumeRequest) { conversation in
            Button("Resume Here") { store.resume(conversation) }
            Button("Cancel", role: .cancel) {}
        } message: { conversation in
            Text("It is still open in another terminal. Quit it there first (/exit in Claude Code, "
                 + "Ctrl-C in Codex): running one conversation in two places mixes up its history."
                 + (conversation.isRecentlyActive() ? "\n\nIt was working in the last two minutes." : ""))
        }
        .overlay {
            if store.sessions.isEmpty && store.elsewhere.isEmpty {
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
    private func row(_ entry: SessionListLayout.Entry, _ shortcuts: [UUID: Int]) -> some View {
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
                           handoverProgress: store.handoverProgress[session.id],
                           shortcutNumber: shortcuts[session.id])
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
