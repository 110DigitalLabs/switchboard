import Foundation

extension SessionStore {
    /// Applies a hook event to its row. Events for unknown rows are ignored.
    func handle(_ event: AgentEvent) {
        guard var session = sessions.first(where: { $0.id == event.rowID }) else { return }
        let previousDirectory = session.workingDirectory

        if let id = event.conversationID, id != session.agentConversationID {
            switch event.kind {
            case .sessionStarted, .promptSubmitted, .turnFinished:
                // A new conversation in the same terminal (e.g. after Ctrl-C
                // and a relaunch) takes over the row.
                if session.agentConversationID != nil {
                    session.agentTitle = nil
                    session.workingDirectory = nil
                    session.statusLine = nil
                }
                session.agentConversationID = id
            default:
                if session.agentConversationID == nil { session.agentConversationID = id }
            }
        }
        if let cwd = event.cwd, Self.tracksWorkingDirectory(event.kind) || session.workingDirectory == nil {
            session.workingDirectory = cwd
        }
        if let model = event.model { session.agentModel = model }
        if let title = event.title { session.agentTitle = title }
        switch event.kind {
        case .statusLine(let output):
            session.statusLine = output.isEmpty ? nil : output
        case .sessionEnded:
            // The model and context it showed belong to a conversation that is over.
            session.statusLine = nil
        default:
            break
        }

        let taggedTicket = TicketTagging.ticket(toTag: session, prompt: event.prompt,
                                                teamKeys: ticketSource?.teamKeys ?? [])
        if let taggedTicket { session.ticketID = taggedTicket }

        let wantsAttention = session.activity.apply(event.kind)
        if wantsAttention {
            if selectedID == session.id && isAppActive() {
                session.activity.markViewed()
            } else {
                session.hasBadge = true
                notifier?.post(title: session.title, body: session.workingState.label, rowID: session.id)
            }
        }

        update(session)
        if !event.prURLs.isEmpty {
            attachPullRequests(event.prURLs, to: session.id)
        }
        if session.kind == .worktree, session.workingDirectory != previousDirectory {
            onPullRequestSourcesChanged?()
        }

        if event.kind == .sessionStarted {
            terminals.terminal(for: session.id)?.agentDidStart()
        }
        if let taggedTicket {
            loadTicketDetails(taggedTicket, rowID: session.id)
        }
        if session.agentTitle == nil, let path = event.transcriptPath, session.agent == .claudeCode,
           event.kind == .sessionStarted || event.kind == .turnFinished {
            loadTitle(fromTranscript: path, rowID: session.id, conversationID: session.agentConversationID)
        }
    }

    /// Events that report where the conversation itself runs. Tool events are
    /// skipped so a tool's own `cd` cannot move where the row resumes.
    private static func tracksWorkingDirectory(_ kind: AgentEvent.Kind) -> Bool {
        switch kind {
        case .sessionStarted, .promptSubmitted, .turnFinished: true
        default: false
        }
    }

    /// Fallback for when no status line has reported `session_name` yet.
    private func loadTitle(fromTranscript path: String, rowID: UUID, conversationID: String?) {
        Task {
            let title = await Task.detached(priority: .utility) {
                ClaudeTranscript.title(fromTranscriptAt: path)
            }.value
            guard let title,
                  var session = sessions.first(where: { $0.id == rowID }),
                  session.agentConversationID == conversationID,
                  session.agentTitle == nil
            else { return }
            session.agentTitle = title
            update(session)
        }
    }

    func handleHookData(_ data: Data) {
        guard let message = HookMessage(data: data),
              let event = AgentEventDecoder.decode(message) else { return }
        handle(event)
    }
}
