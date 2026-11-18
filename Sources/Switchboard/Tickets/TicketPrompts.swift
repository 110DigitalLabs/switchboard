import Foundation

/// The short prompts Switchboard puts in front of the agent for ticket
/// sessions. Single lines: they are typed into a terminal.
enum TicketPrompts {
    /// Typed (not submitted) into a temp planning session.
    static func planning(ticketID: String, title: String?) -> String {
        "Let's plan \(label(ticketID, title)). The ticket is in \(TicketFolder.ticketFileName). "
    }

    /// Typed (not submitted) into a worktree or folder session.
    static func work(ticketID: String, title: String?) -> String {
        "Let's work on \(label(ticketID, title)). "
    }

    static func draft(for session: Session) -> String? {
        guard let id = session.ticketID else { return nil }
        return session.kind == .temp
            ? planning(ticketID: id, title: session.ticketTitle)
            : work(ticketID: id, title: session.ticketTitle)
    }

    private static func label(_ id: String, _ title: String?) -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return id }
        return "\(id) (\(singleLine(title)))"
    }

    /// External text made safe to type: one line, no controls or escapes.
    static func singleLine(_ text: String) -> String {
        TypedText.sanitize(text).trimmingCharacters(in: .whitespaces)
    }
}
