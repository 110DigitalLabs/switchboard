import Foundation

/// The session list as shown: sections of rows, possibly nested under ticket
/// parents, plus the flat order Cmd-1…9 and Cmd-Up/Down navigate.
struct SessionListLayout: Equatable {
    struct Entry: Identifiable, Equatable {
        let session: Session
        /// The ticket with its -A/-B suffix, when the session has one.
        let ticketLabel: String?
        var id: UUID { session.id }
    }

    struct TicketGroup: Identifiable, Equatable {
        /// Collapse key, `ticket:<ID>`.
        let id: String
        let ticketID: String
        /// The Linear title, when a session or the assigned issue knows it.
        let title: String?
        /// Union of the children's PR URLs, in first-seen order.
        let prURLs: [String]
        let entries: [Entry]
        let isCollapsed: Bool
        /// Set for an assigned issue no session works on yet; `entries` is
        /// then empty.
        var unstartedIssue: LinearIssue? = nil
    }

    enum Item: Identifiable, Equatable {
        case session(Entry)
        case ticket(TicketGroup)

        var id: String {
            switch self {
            case .session(let entry): entry.id.uuidString
            case .ticket(let group): group.id
            }
        }
    }

    struct Section: Identifiable, Equatable {
        /// Collapse key.
        let id: String
        let title: String
        let items: [Item]
        let isCollapsed: Bool
        /// The folder a Folders section stands for, for its "+".
        var folderPath: String? = nil
    }

    var sections: [Section]

    /// The ⌘1–⌘9 number for each session that has one: its 1-based position
    /// in `visibleOrder`, the same order `selectVisible(position:)` uses.
    var shortcutNumbers: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: visibleOrder.prefix(9).enumerated().map { ($1, $0 + 1) })
    }

    /// Session IDs in on-screen order, skipping collapsed sections,
    /// collapsed ticket groups and kept (closed) rows, which have no terminal.
    var visibleOrder: [UUID] {
        sections.filter { !$0.isCollapsed }.flatMap { section in
            section.items.flatMap { item -> [UUID] in
                switch item {
                case .session(let entry): entry.session.isKept ? [] : [entry.id]
                case .ticket(let group): group.isCollapsed ? [] : group.entries.map(\.id)
                }
            }
        }
    }
}
