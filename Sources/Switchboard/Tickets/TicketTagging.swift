import Foundation

/// Tagging a session with a ticket the user mentions in a prompt.
enum TicketTagging {
    /// The ticket to tag the session with: the first valid mention, and only
    /// when the session has no ticket yet and the user hasn't chosen one by
    /// hand. The session never moves.
    static func ticket(toTag session: Session, prompt: String?, teamKeys: Set<String>) -> String? {
        guard session.ticketID == nil, !session.ticketSetByUser, let prompt, !prompt.isEmpty else { return nil }
        return TicketMentions.find(in: prompt, validTeamKeys: teamKeys).first
    }
}

/// What the session store needs from the Linear account.
@MainActor
protocol TicketSource: AnyObject {
    var teamKeys: Set<String> { get }
    var isConnected: Bool { get }
    var service: LinearService? { get }
}

extension LinearAccount: TicketSource {}
