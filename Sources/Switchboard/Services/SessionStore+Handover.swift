import Foundation

extension SessionStore {
    /// "Move to worktree…": summarizes the conversation on a fork, starts a
    /// fresh agent in a new worktree of `repo` with the ticket and summary,
    /// and swaps it into the same row. The row is untouched on failure.
    func moveToWorktree(_ id: UUID, repo: Repo, startTerminal: Bool = true,
                        isRepo: (URL) -> Bool = RepoScanner.isGitRepo) async {
        guard handoverProgress[id] == nil,
              let session = sessions.first(where: { $0.id == id }), session.canMoveToWorktree else { return }
        defer { handoverProgress[id] = nil }

        var ticketURL: URL?
        if let ticketID = session.ticketID, let source = ticketSource, source.isConnected,
           let service = source.service {
            handoverProgress[id] = "Fetching \(ticketID)…"
            ticketURL = try? await service.issue(identifier: ticketID).url
        }
        var summary: String?
        if let conversation = session.agentConversationID,
           let arguments = HandoverCommand.summaryArguments(agent: session.agent, conversationID: conversation) {
            handoverProgress[id] = "Summarizing the conversation…"
            do {
                summary = try await runSummary(HandoverCommand.shellLine(arguments),
                                               session.workingDirectory ?? session.folderPath)
            } catch {
                errorMessage = "Could not summarize the conversation for the handover: \(error.localizedDescription)"
                return
            }
        }

        handoverProgress[id] = "Starting the worktree session…"
        var summaryFile: String?
        if let summary, HandoverCommand.needsFile(summary) {
            let url = HandoverCommand.summaryFileURL(in: handoverDirectory, session: session, at: Date())
            do {
                try FileManager.default.createDirectory(at: handoverDirectory, withIntermediateDirectories: true)
                try (summary + "\n").write(to: url, atomically: true, encoding: .utf8)
                summaryFile = url.path
            } catch {
                errorMessage = "Could not save the handover summary: \(error.localizedDescription)"
                return
            }
        }

        // The row may have been closed or retagged while the summary ran.
        guard let current = sessions.first(where: { $0.id == id }) else { return }
        let prompt = HandoverCommand.initialPrompt(ticketID: current.ticketID, ticketTitle: current.ticketTitle,
                                                   ticketURL: ticketURL, summary: summary, summaryFile: summaryFile)
        swapRow(current.handedOver(to: repo, isRepo: isRepo),
                options: AgentLaunchOptions(prompt: prompt), startTerminal: startTerminal)
    }

    /// Replaces a row in place: same ID and position, the old terminal
    /// terminated and a new one started for the new folder.
    func swapRow(_ replacement: Session, options: AgentLaunchOptions, startTerminal: Bool = true) {
        guard sessions.contains(where: { $0.id == replacement.id }) else { return }
        terminals.remove(replacement.id)
        update(replacement)
        guard startTerminal else { return }
        openTerminal(for: replacement, launch: .fresh(replacement, hooks: terminals.hooks, options: options))
        selectedID = replacement.id
    }
}
