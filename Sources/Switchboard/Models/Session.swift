import Foundation

/// One row: a terminal, a folder, an agent, and later a ticket and PRs.
struct Session: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: SessionKind
    var folderPath: String
    var agent: Agent
    let createdAt: Date

    var agentConversationID: String?
    /// Where the agent actually runs, from hook payloads. For worktree
    /// sessions this is the worktree the agent created, not `folderPath`.
    var workingDirectory: String?
    var agentTitle: String?
    var ticketID: String?
    /// The user set or cleared the ticket by hand, so prompts that mention
    /// a ticket no longer tag this row.
    var ticketSetByUser = false
    /// The Linear issue's title; display stays agentTitle → ticketID → folder.
    var ticketTitle: String?
    /// Filled in by the Linear integration (stage 4).
    var linearProjectName: String?
    var prURLs: [String] = []
    var agentModel: String?
    /// The user's own Claude Code status line as last rendered, escape codes
    /// and all. Live only: not saved.
    var statusLine: String?
    var activity = RowActivity()
    /// Shown on the row from a finished / needs-input event until it is viewed.
    var hasBadge = false
    /// Set when a temp or scratch row was closed and its folder kept: the row
    /// stays, without a terminal, in the Temp group until cleanup deletes it.
    var closedAt: Date?

    var isKept: Bool { closedAt != nil }

    init(id: UUID = UUID(), kind: SessionKind, folderPath: String, agent: Agent, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.folderPath = folderPath
        self.agent = agent
        self.createdAt = createdAt
    }

    var folderName: String { URL(fileURLWithPath: folderPath).lastPathComponent }

    var title: String { agentTitle ?? ticketID ?? folderName }

    var workingState: WorkingState {
        get { activity.state }
        set { activity.state = newValue }
    }

    func launchCommand(hooks: HookInstallation?, options: AgentLaunchOptions = AgentLaunchOptions()) -> String? {
        agent.launchCommand(for: kind, hooks: hooks, options: options)
    }
}
