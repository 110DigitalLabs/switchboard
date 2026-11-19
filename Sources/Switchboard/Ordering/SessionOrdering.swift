import Foundation

/// Sorts and groups sessions into a `SessionListLayout`. Pure.
enum SessionOrdering {
    static let scratchSectionID = "scratch"
    static let tempSectionID = "temp"
    static let ticketsSectionID = "tickets"
    static let noTicketSectionID = "no-ticket"

    /// `assigned` are the user's Linear issues; those no session works on
    /// yet appear in Tickets mode as parents without children.
    static func layout(sessions: [Session], sort: SessionSort, grouping: SessionGrouping,
                       assigned: [LinearIssue] = [], collapsed: Set<String> = []) -> SessionListLayout {
        let labels = TicketSuffixes.labels(for: sessions)
        func entries(_ group: [Session]) -> [SessionListLayout.Entry] {
            sorted(group, by: sort).map { .init(session: $0, ticketLabel: labels[$0.id]) }
        }
        func section(_ id: String, _ title: String, _ items: [SessionListLayout.Item],
                     folderPath: String? = nil) -> SessionListLayout.Section {
            .init(id: id, title: title, items: items, isCollapsed: collapsed.contains(id), folderPath: folderPath)
        }

        let main = sessions.filter { !$0.kind.isBottomGrouped && !$0.isKept }
        // In Tickets mode a live scratch or temp session on a ticket sits
        // under that ticket, not at the bottom, so moving it to a ticket or
        // starting a planning session from an assigned issue keeps the
        // ticket visible.
        let ticketedBottom = grouping == .ticket
            ? sessions.filter { $0.kind.isBottomGrouped && !$0.isKept && $0.ticketID != nil }
            : []
        let onTicket = Set(ticketedBottom.map(\.id))
        var sections: [SessionListLayout.Section] = []

        switch grouping {
        case .folder:
            let groups = Dictionary(grouping: main) { $0.folderPath }
            let paths = groups.keys.sorted {
                let a = URL(fileURLWithPath: $0).lastPathComponent, b = URL(fileURLWithPath: $1).lastPathComponent
                return a == b ? precedes($0, $1) : precedes(a, b)
            }
            for path in paths {
                let title = URL(fileURLWithPath: path).lastPathComponent
                sections.append(section("folder:\(path)", title, entries(groups[path]!).map { .session($0) },
                                        folderPath: path))
            }
        case .ticket:
            let unstarted = TicketSessions.unstarted(assigned, sessions: sessions).map { issue in
                SessionListLayout.Item.ticket(.init(
                    id: "ticket:\(issue.identifier)", ticketID: issue.identifier, title: issue.title,
                    prURLs: [], entries: [], isCollapsed: false, unstartedIssue: issue))
            }
            let tickets = ticketGroups(main + ticketedBottom, sort: sort, labels: labels, collapsed: collapsed) + unstarted
            if !tickets.isEmpty {
                sections.append(section(ticketsSectionID, "Tickets", tickets))
            }
            let loose = main.filter { $0.ticketID == nil }
            if !loose.isEmpty {
                sections.append(section(noTicketSectionID, "No Ticket", entries(loose).map { .session($0) }))
            }
        }

        let scratch = sessions.filter { $0.kind == .scratch && !$0.isKept && !onTicket.contains($0.id) }
        if !scratch.isEmpty {
            sections.append(section(scratchSectionID, "Scratch", entries(scratch).map { .session($0) }))
        }
        // Live temp rows, then kept (closed) temp and scratch rows, newest
        // closed first.
        let temp = sessions.filter { $0.kind == .temp && !$0.isKept && !onTicket.contains($0.id) }
        let kept = sessions.filter(\.isKept).sorted {
            ($0.closedAt!, $0.id.uuidString) > ($1.closedAt!, $1.id.uuidString)
        }
        if !temp.isEmpty || !kept.isEmpty {
            let items = entries(temp) + kept.map { .init(session: $0, ticketLabel: labels[$0.id]) }
            sections.append(section(tempSectionID, "Temp", items.map { .session($0) }))
        }
        return SessionListLayout(sections: sections)
    }

    /// Ticket parents with sessions, in ticket order.
    private static func ticketGroups(_ sessions: [Session], sort: SessionSort, labels: [UUID: String],
                                     collapsed: Set<String>) -> [SessionListLayout.Item] {
        let byTicket = Dictionary(grouping: sessions.filter { $0.ticketID != nil }) { $0.ticketID! }
        return byTicket.keys.sorted(by: precedes).map { ticket in
            let children = sorted(byTicket[ticket]!, by: sort)
            var seen = Set<String>()
            let prs = children.flatMap(\.prURLs).filter { seen.insert($0).inserted }
            let key = "ticket:\(ticket)"
            return .ticket(.init(id: key, ticketID: ticket, title: children.lazy.compactMap(\.ticketTitle).first,
                                 prURLs: prs,
                                 entries: children.map { .init(session: $0, ticketLabel: labels[$0.id]) },
                                 isCollapsed: collapsed.contains(key)))
        }
    }

    static func sorted(_ sessions: [Session], by sort: SessionSort) -> [Session] {
        sessions.sorted { a, b in
            switch sort {
            case .ticket:
                if let order = compareTickets(a.ticketID, b.ticketID) { return order }
                if let order = compare(a.folderName, b.folderName) { return order }
            case .folder:
                if let order = compare(a.folderName, b.folderName) { return order }
                if let order = compareTickets(a.ticketID, b.ticketID) { return order }
            }
            return (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
        }
    }

    /// Natural order (XYZ-9 before XYZ-10); missing tickets go last.
    private static func compareTickets(_ a: String?, _ b: String?) -> Bool? {
        switch (a, b) {
        case (nil, nil): nil
        case (nil, _): false
        case (_, nil): true
        case let (a?, b?): compare(a, b)
        }
    }

    /// nil when the two are equal.
    private static func compare(_ a: String, _ b: String) -> Bool? {
        switch a.compare(b, options: [.numeric, .caseInsensitive]) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: a == b ? nil : a < b
        }
    }

    static func precedes(_ a: String, _ b: String) -> Bool {
        compare(a, b) ?? false
    }
}
