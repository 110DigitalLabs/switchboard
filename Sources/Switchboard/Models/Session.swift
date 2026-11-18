import Foundation

/// One row: a terminal, a folder, an agent, and later a ticket and PRs.
struct Session: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: SessionKind
    var folderPath: String
    var agent: Agent
    let createdAt: Date

    // Filled in by later stages (hooks, Linear, GitHub).
    var agentConversationID: String?
    var agentTitle: String?
    var ticketID: String?
    var prURLs: [String] = []
    var workingState: WorkingState = .idle

    init(id: UUID = UUID(), kind: SessionKind, folderPath: String, agent: Agent, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.folderPath = folderPath
        self.agent = agent
        self.createdAt = createdAt
    }

    var folderName: String { URL(fileURLWithPath: folderPath).lastPathComponent }

    var title: String { agentTitle ?? ticketID ?? folderName }

    var launchCommand: String { agent.launchCommand(for: kind) }
}
