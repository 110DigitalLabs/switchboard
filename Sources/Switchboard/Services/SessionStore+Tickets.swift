import Foundation

extension SessionStore {
    /// Starts a session on a Linear issue: a planning session in a temp
    /// folder holding TICKET.md, or the agent's worktree mode in a repo.
    /// Either way the agent gets a short prompt typed but not submitted.
    func startTicketSession(_ issue: LinearIssue, destination: TicketDestination, agent: Agent,
                            startTerminal: Bool = true) {
        let tempFolder = TicketFolder.url(for: issue.identifier, in: settings.homeFolder)
        if destination == .tempFolder {
            do {
                try TicketFolder.create(for: issue, in: settings.homeFolder)
            } catch {
                errorMessage = "Could not create the ticket folder: \(error.localizedDescription)"
                return
            }
        }
        let session = TicketSessions.newSession(for: issue, destination: destination, agent: agent,
                                                tempFolder: tempFolder)
        addTicketSession(session, startTerminal: startTerminal)
    }

    /// The "+" on an existing ticket session: another session on that
    /// ticket in the same kind of folder.
    func addSibling(of id: UUID, startTerminal: Bool = true) {
        guard let original = sessions.first(where: { $0.id == id }) else { return }
        let sibling = TicketSessions.sibling(of: original)
        if sibling.kind == .temp {
            try? FileManager.default.createDirectory(atPath: sibling.folderPath, withIntermediateDirectories: true)
        }
        addTicketSession(sibling, startTerminal: startTerminal)
    }

    private func addTicketSession(_ session: Session, startTerminal: Bool) {
        add(session, startTerminal: startTerminal,
            options: AgentLaunchOptions(planMode: session.kind == .temp),
            draft: TicketPrompts.draft(for: session))
    }

    /// Fills in the title and project of a ticket found in a prompt.
    func loadTicketDetails(_ ticketID: String, rowID: UUID) {
        guard let source = ticketSource, source.isConnected, let service = source.service else { return }
        Task {
            guard let issue = try? await service.issue(identifier: ticketID),
                  var session = sessions.first(where: { $0.id == rowID }),
                  session.ticketID == ticketID else { return }
            session.ticketTitle = issue.title
            session.linearProjectName = issue.projectName
            update(session)
        }
    }
}
