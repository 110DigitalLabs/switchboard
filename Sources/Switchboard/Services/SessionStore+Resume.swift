import Foundation

extension SessionStore {
    /// Conversations rows here already own, which the resume list leaves out.
    var ownedConversationIDs: Set<String> {
        Set(sessions.compactMap(\.agentConversationID))
    }

    /// How often the Running Elsewhere section looks for agents.
    static let elsewhereInterval: Duration = .seconds(5)

    /// Keeps `elsewhere` current, scanning off the main thread.
    func startWatchingElsewhere() {
        elsewhereTask?.cancel()
        elsewhereTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await Task.detached(priority: .utility) { ActiveConversations.list() }.value
                guard let self else { return }
                self.updateElsewhere(found)
                try? await Task.sleep(for: Self.elsewhereInterval)
            }
        }
    }

    /// Leaves out conversations a row here already owns.
    func updateElsewhere(_ found: [PastConversation]) {
        let owned = ownedConversationIDs
        let visible = found.filter { !owned.contains($0.conversationID) }
        if visible != elsewhere { elsewhere = visible }
    }

    /// Opens a saved conversation in a new folder row, resumed where it ran.
    /// A row that already owns it is selected instead.
    func resume(_ conversation: PastConversation) {
        if let owner = sessions.first(where: { $0.agentConversationID == conversation.conversationID }) {
            selectedID = owner.id
            return
        }
        let session = Self.row(resuming: conversation)
        add(session, startTerminal: false)
        openTerminal(for: session, launch: .reopen(session, hooks: terminals.hooks))
        selectedID = session.id
        elsewhere.removeAll { $0.conversationID == conversation.conversationID }
    }

    static func row(resuming conversation: PastConversation) -> Session {
        var session = Session(kind: .folder, folderPath: conversation.directory, agent: conversation.agent)
        session.agentConversationID = conversation.conversationID
        session.agentTitle = conversation.title ?? conversation.firstPrompt
        return session
    }
}
