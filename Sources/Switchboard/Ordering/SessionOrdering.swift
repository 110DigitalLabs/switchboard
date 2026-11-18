import Foundation

/// Sorts and groups sessions into a `SessionListLayout`. Pure.
enum SessionOrdering {
    static let scratchSectionID = "scratch"
    static let tempSectionID = "temp"
    static let noProjectTitle = "No project"

    static func layout(sessions: [Session], sort: SessionSort, grouping: SessionGrouping,
                       collapsed: Set<String> = []) -> SessionListLayout {
        let labels = TicketSuffixes.labels(for: sessions)
        func entries(_ group: [Session]) -> [SessionListLayout.Entry] {
            sorted(group, by: sort).map { .init(session: $0, ticketLabel: labels[$0.id]) }
        }
        func section(_ id: String, _ title: String, _ items: [SessionListLayout.Item]) -> SessionListLayout.Section {
            .init(id: id, title: title, items: items, isCollapsed: collapsed.contains(id))
        }

        let main = sessions.filter { !$0.kind.isBottomGrouped }
        var sections: [SessionListLayout.Section] = []

        switch grouping {
        case .none:
            if !main.isEmpty {
                sections.append(section("sessions", "Sessions", entries(main).map { .session($0) }))
            }
        case .project:
            let groups = Dictionary(grouping: main) { $0.linearProjectName }
            let named = groups.keys.compactMap { $0 }.sorted(by: precedes)
            for name in named {
                sections.append(section("project:\(name)", name, entries(groups[name]!).map { .session($0) }))
            }
            if let unassigned = groups[nil] {
                sections.append(section("project:", noProjectTitle, entries(unassigned).map { .session($0) }))
            }
        case .folder:
            let groups = Dictionary(grouping: main) { $0.folderPath }
            let paths = groups.keys.sorted {
                let a = URL(fileURLWithPath: $0).lastPathComponent, b = URL(fileURLWithPath: $1).lastPathComponent
                return a == b ? precedes($0, $1) : precedes(a, b)
            }
            for path in paths {
                let title = URL(fileURLWithPath: path).lastPathComponent
                sections.append(section("folder:\(path)", title, entries(groups[path]!).map { .session($0) }))
            }
        case .ticket:
            if !main.isEmpty {
                sections.append(section("sessions", "Sessions", ticketItems(main, sort: sort, labels: labels,
                                                                            collapsed: collapsed)))
            }
        }

        let scratch = sessions.filter { $0.kind == .scratch }
        if !scratch.isEmpty {
            sections.append(section(scratchSectionID, "Scratch", entries(scratch).map { .session($0) }))
        }
        let temp = sessions.filter { $0.kind == .temp }
        if !temp.isEmpty {
            sections.append(section(tempSectionID, "Temp", entries(temp).map { .session($0) }))
        }
        return SessionListLayout(sections: sections)
    }

    /// Ticket parents in ticket order, then sessions without a ticket.
    private static func ticketItems(_ sessions: [Session], sort: SessionSort, labels: [UUID: String],
                                     collapsed: Set<String>) -> [SessionListLayout.Item] {
        let byTicket = Dictionary(grouping: sessions.filter { $0.ticketID != nil }) { $0.ticketID! }
        var items: [SessionListLayout.Item] = byTicket.keys.sorted(by: precedes).map { ticket in
            let children = sorted(byTicket[ticket]!, by: sort)
            var seen = Set<String>()
            let prs = children.flatMap(\.prURLs).filter { seen.insert($0).inserted }
            let key = "ticket:\(ticket)"
            return .ticket(.init(id: key, ticketID: ticket, prURLs: prs,
                                 entries: children.map { .init(session: $0, ticketLabel: labels[$0.id]) },
                                 isCollapsed: collapsed.contains(key)))
        }
        items += sorted(sessions.filter { $0.ticketID == nil }, by: sort)
            .map { .session(.init(session: $0, ticketLabel: nil)) }
        return items
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
