import Foundation

extension SessionStore {
    /// Conversations rows here already own, which the resume list leaves out.
    var ownedConversationIDs: Set<String> {
        Set(sessions.compactMap(\.agentConversationID))
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
    }

    static func row(resuming conversation: PastConversation) -> Session {
        var session = Session(kind: .folder, folderPath: conversation.directory, agent: conversation.agent)
        session.agentConversationID = conversation.conversationID
        session.agentTitle = conversation.title ?? conversation.firstPrompt
        return session
    }
}
