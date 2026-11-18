import Foundation

/// Building the commands and prompt for moving a session into a worktree.
enum HandoverCommand {
    static let summaryPrompt = """
        Summarize this conversation for a handover: a fresh session will continue the work in a new \
        git worktree and will see nothing but your summary. Cover the goal, decisions made and why, \
        what is done, what is left, open questions, and the files involved. Reply with the summary only.
        """

    /// The agent's non-interactive command for summarizing a conversation
    /// on a fork, so the original conversation is untouched. Nil when the
    /// agent has no way to fork headlessly.
    /// - `claude -p --resume <id> --fork-session --no-session-persistence <prompt>`
    /// - `codex exec fork --ephemeral --skip-git-repo-check <id> <prompt>`
    static func summaryArguments(agent: Agent, conversationID: String) -> [String]? {
        switch agent {
        case .claudeCode:
            ["claude", "-p", "--resume", conversationID, "--fork-session",
             "--no-session-persistence", summaryPrompt]
        case .codex:
            ["codex", "exec", "fork", "--ephemeral", "--skip-git-repo-check",
             conversationID, summaryPrompt]
        case .geminiCLI, .cursorAgent:
            // Both can resume headlessly, but only by appending to the
            // original conversation.
            nil
        case .terminal:
            nil
        }
    }

    /// A shell line that replaces the shell with the command.
    static func shellLine(_ arguments: [String]) -> String {
        "exec " + arguments.map(ShellQuote.quoteIfNeeded).joined(separator: " ")
    }

    /// Summaries longer than this, or on several lines, go to a file the
    /// prompt references; the prompt itself is typed into a terminal.
    static let inlineLimit = 400

    static func needsFile(_ summary: String) -> Bool {
        summary.count > inlineLimit || summary.contains(where: \.isNewline)
    }

    /// The new session's first, submitted prompt.
    static func initialPrompt(ticketID: String?, ticketTitle: String?, ticketURL: URL?,
                              summary: String?, summaryFile: String?) -> String {
        var parts: [String] = []
        if let ticketID {
            var ticket = ticketID
            if let title = ticketTitle, !title.isEmpty { ticket += " (\(TicketPrompts.singleLine(title)))" }
            if let ticketURL { ticket += ", \(ticketURL.absoluteString)" }
            parts.append("We're continuing work on \(ticket) in this new worktree.")
        } else {
            parts.append("We're continuing work from an earlier session in this new worktree.")
        }
        if let summaryFile {
            parts.append("Read the handover summary from the previous session in \(summaryFile) first.")
        } else if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append("Handover summary from the previous session: \(summary)")
        }
        parts.append("Then tell me where things stand before changing anything.")
        return parts.joined(separator: " ")
    }

    /// `<directory>/<ticket or row>-<time>.md`.
    static func summaryFileURL(in directory: URL, session: Session, at date: Date) -> URL {
        let base = session.ticketID ?? String(session.id.uuidString.prefix(8))
        return directory.appendingPathComponent("\(base)-\(ScratchFolder.name(for: date)).md")
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Switchboard/handovers", isDirectory: true)
    }
}

extension Session {
    /// The row after moving into a fresh worktree of `repo`: same ID, ticket
    /// and PRs; new folder and kind; no conversation until the new agent
    /// reports one.
    func handedOver(to repo: Repo, isRepo: (URL) -> Bool = RepoScanner.isGitRepo) -> Session {
        var next = Session(id: id, kind: NewSessionTarget.kind(forFolder: repo.url, agent: agent, isRepo: isRepo),
                           folderPath: repo.url.path, agent: agent, createdAt: createdAt)
        next.ticketID = ticketID
        next.ticketTitle = ticketTitle
        next.linearProjectName = linearProjectName
        next.prURLs = prURLs
        return next
    }

    /// Folder and temp agent sessions with something to carry over.
    var canMoveToWorktree: Bool {
        agent != .terminal && (kind == .folder || kind == .temp) && (ticketID != nil || agentConversationID != nil)
    }
}
