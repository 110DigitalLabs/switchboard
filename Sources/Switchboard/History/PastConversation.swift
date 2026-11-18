import Foundation

/// A conversation an agent saved to its own history, which Switchboard can
/// reopen in a new row with the agent's resume command.
struct PastConversation: Identifiable, Hashable, Sendable {
    let agent: Agent
    let conversationID: String
    /// Where the agent ran it; resuming happens there.
    let directory: String
    let title: String?
    let firstPrompt: String?
    let lastActive: Date

    var id: String { "\(agent.rawValue):\(conversationID)" }

    var displayTitle: String {
        title ?? firstPrompt ?? URL(fileURLWithPath: directory).lastPathComponent
    }

    /// Written to within `window`: probably still open in another terminal,
    /// where resuming it here too would run one conversation in two places.
    func isRecentlyActive(now: Date = Date(), window: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(lastActive) < window
    }
}
