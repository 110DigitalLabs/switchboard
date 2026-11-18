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
        .modifier(ChangeTicketDialog())
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
                    ticketMenu(for: session)
                    Divider()
                    Button("Close Session") { store.requestClose(session.id) }
                }
        }
    }
}

extension SessionListView {
    /// Fixes a row that was grouped under the wrong ticket.
    @ViewBuilder
    private func ticketMenu(for session: Session) -> some View {
        let others = store.ticketIDs(excluding: session.id)
        Menu("Move to Ticket") {
            ForEach(others, id: \.self) { id in
                Button(id) { store.setTicket(id, for: session.id) }
            }
            if !others.isEmpty { Divider() }
            Button("Other Ticket…") { store.ticketEditRequestID = session.id }
            if session.ticketID != nil {
                Divider()
                Button("Remove from \(session.ticketID!)") { store.setTicket(nil, for: session.id) }
            }
        }
    }
}

/// "Move to ticket": type a ticket ID or paste a Linear URL.
private struct ChangeTicketDialog: ViewModifier {
    @Environment(SessionStore.self) private var store
    @State private var text = ""

    func body(content: Content) -> some View {
        let session = store.ticketEditRequestID.flatMap { id in store.sessions.first { $0.id == id } }
        content.alert(
            "Move “\(session?.title ?? "")” to Ticket",
            isPresented: Binding(get: { session != nil }, set: { if !$0 { store.ticketEditRequestID = nil } }),
            presenting: session
        ) { session in
            TextField("ENG-123 or Linear URL", text: $text)
            Button("Move") {
                if !store.setTicket(text, for: session.id) {
                    store.errorMessage = "“\(text)” is not a ticket ID or Linear URL."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The session moves to that ticket's group. Leave it empty to take it out of any ticket.")
        }
        .onChange(of: store.ticketEditRequestID) { _, id in
            text = id.flatMap { id in store.sessions.first { $0.id == id }?.ticketID } ?? ""
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
