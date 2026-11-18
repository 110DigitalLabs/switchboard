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
        /// Union of the children's PR URLs, in first-seen order.
        let prURLs: [String]
        let entries: [Entry]
        let isCollapsed: Bool
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
    }

    var sections: [Section]

    /// Session IDs in on-screen order, skipping collapsed sections and
    /// collapsed ticket groups.
    var visibleOrder: [UUID] {
        sections.filter { !$0.isCollapsed }.flatMap { section in
            section.items.flatMap { item -> [UUID] in
                switch item {
                case .session(let entry): [entry.id]
                case .ticket(let group): group.isCollapsed ? [] : group.entries.map(\.id)
                }
            }
        }
    }
}
