import Foundation

extension SessionStore {
    /// Applies a hook event to its row. Events for unknown rows are ignored.
    func handle(_ event: AgentEvent) {
        guard var session = sessions.first(where: { $0.id == event.rowID }) else { return }

        if let id = event.conversationID, id != session.agentConversationID {
            switch event.kind {
            case .sessionStarted, .promptSubmitted, .turnFinished:
                // A new conversation in the same terminal (e.g. after Ctrl-C
                // and a relaunch) takes over the row.
                if session.agentConversationID != nil {
                    session.agentTitle = nil
                    session.statusText = nil
                }
                session.agentConversationID = id
            default:
                if session.agentConversationID == nil { session.agentConversationID = id }
            }
        }
        if let model = event.model { session.agentModel = model }
        if let title = event.title { session.agentTitle = title }
        if case .statusLine(let raw) = event.kind {
            let text = StatusLineText.singleLine(raw)
            session.statusText = text.isEmpty ? nil : text
        }

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

        if session.agentTitle == nil, let path = event.transcriptPath, session.agent == .claudeCode,
           event.kind == .sessionStarted || event.kind == .turnFinished {
            loadTitle(fromTranscript: path, rowID: session.id, conversationID: session.agentConversationID)
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
