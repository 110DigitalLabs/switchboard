import Foundation

/// Pure rules for sessions that carry Linear tickets.
enum TicketSessions {
    /// Local sessions on a ticket, oldest first (the -A, -B … order).
    static func existing(for ticketID: String, in sessions: [Session]) -> [Session] {
        sessions
            .filter { $0.ticketID?.caseInsensitiveCompare(ticketID) == .orderedSame }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// Assigned issues no local session works on yet, in Linear's order.
    static func unstarted(_ issues: [LinearIssue], sessions: [Session]) -> [LinearIssue] {
        let started = Set(sessions.compactMap { $0.ticketID?.uppercased() })
        return issues.filter { !started.contains($0.identifier.uppercased()) }
    }

    /// A new session for the issue at a destination. Temp sessions get a
    /// planning folder that the caller creates.
    static func newSession(for issue: LinearIssue, destination: TicketDestination, agent: Agent,
                           tempFolder: URL, isRepo: (URL) -> Bool = RepoScanner.isGitRepo) -> Session {
        var session: Session
        switch destination {
        case .tempFolder:
            session = Session(kind: .temp, folderPath: tempFolder.path, agent: agent)
        case .repo(let repo):
            session = Session(kind: NewSessionTarget.kind(forFolder: repo.url, agent: agent, isRepo: isRepo),
                              folderPath: repo.url.path, agent: agent)
        }
        session.attach(issue)
        return session
    }

    /// Another session on the same ticket in the same kind of folder: a
    /// fresh worktree of the same repo, or the same temp / plain folder.
    static func sibling(of session: Session, now: Date = Date()) -> Session {
        var copy = Session(kind: session.kind, folderPath: session.folderPath, agent: session.agent, createdAt: now)
        copy.ticketID = session.ticketID
        copy.ticketTitle = session.ticketTitle
        copy.linearProjectName = session.linearProjectName
        return copy
    }
}

extension Session {
    mutating func attach(_ issue: LinearIssue) {
        ticketID = issue.identifier
        ticketTitle = issue.title
        linearProjectName = issue.projectName
    }
}
