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

    /// Moves a row to another ticket's group, or out of any group when
    /// `input` is nil or blank. Accepts an ID ("eng-12") or a Linear URL.
    /// Returns false, changing nothing, when the input isn't a ticket.
    @discardableResult
    func setTicket(_ input: String?, for rowID: UUID) -> Bool {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ticketID: String?
        if trimmed.isEmpty {
            ticketID = nil
        } else if let id = TicketReference.parse(trimmed)?.linearIdentifier {
            ticketID = id
        } else {
            return false
        }
        guard var session = sessions.first(where: { $0.id == rowID }) else { return false }
        session.ticketSetByUser = true
        if session.ticketID != ticketID {
            session.ticketID = ticketID
            // Carry over what a sibling already knows; Linear fills the rest.
            let known = ticketID.flatMap { id in sessions.first { $0.ticketID == id && $0.id != rowID } }
            session.ticketTitle = known?.ticketTitle
            session.linearProjectName = known?.linearProjectName
        }
        update(session)
        if let ticketID, session.ticketTitle == nil { loadTicketDetails(ticketID, rowID: rowID) }
        return true
    }

    /// Tickets other rows are on, for the "Move to Ticket" menu.
    func ticketIDs(excluding rowID: UUID) -> [String] {
        let current = sessions.first { $0.id == rowID }?.ticketID
        let ids = Set(sessions.filter { !$0.isKept }.compactMap(\.ticketID)).subtracting([current].compactMap { $0 })
        return ids.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
