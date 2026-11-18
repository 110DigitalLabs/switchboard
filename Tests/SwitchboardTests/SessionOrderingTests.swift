import Foundation
import Testing
@testable import Switchboard

struct SessionOrderingTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ folder: String, ticket: String? = nil, kind: SessionKind = .folder,
                         project: String? = nil, prs: [String] = [], at offset: TimeInterval = 0) -> Session {
        var s = Session(kind: kind, folderPath: "/w/\(folder)", agent: .claudeCode,
                        createdAt: base.addingTimeInterval(offset))
        s.ticketID = ticket
        s.linearProjectName = project
        s.prURLs = prs
        return s
    }

    private func titles(_ layout: SessionListLayout) -> [String] { layout.sections.map(\.title) }

    @Test func ticketSortIsNaturalWithTicketlessByFolderLast() {
        let sessions = [session("b"), session("x", ticket: "XYZ-10"), session("a"),
                        session("y", ticket: "XYZ-9"), session("z", ticket: "ABC-200")]
        let sorted = SessionOrdering.sorted(sessions, by: .ticket)
        #expect(sorted.map { $0.ticketID ?? $0.folderName } == ["ABC-200", "XYZ-9", "XYZ-10", "a", "b"])
    }

    @Test func folderSortIsByFolderName() {
        let sessions = [session("api-10"), session("api-9"), session("Web")]
        #expect(SessionOrdering.sorted(sessions, by: .folder).map(\.folderName) == ["api-9", "api-10", "Web"])
    }

    @Test func scratchAndTempAlwaysAtBottomInThatOrder() {
        let sessions = [session("t", kind: .temp), session("s", kind: .scratch), session("a"),
                        session("b", project: "Core")]
        for grouping in SessionGrouping.allCases {
            let layout = SessionOrdering.layout(sessions: sessions, sort: .ticket, grouping: grouping)
            #expect(Array(titles(layout).suffix(2)) == ["Scratch", "Temp"], "\(grouping)")
        }
    }

    @Test func projectGroupingPutsUnassignedUnderNoProjectLast() {
        let sessions = [session("a"), session("b", project: "Zeta"), session("c", project: "Alpha")]
        let layout = SessionOrdering.layout(sessions: sessions, sort: .folder, grouping: .project)
        #expect(titles(layout) == ["Alpha", "Zeta", "No project"])
    }

    @Test func folderGroupingMakesOneSectionPerFolder() {
        let sessions = [session("web"), session("api", ticket: "X-2"), session("api", ticket: "X-1")]
        let layout = SessionOrdering.layout(sessions: sessions, sort: .ticket, grouping: .folder)
        #expect(titles(layout) == ["api", "web"])
        #expect(layout.visibleOrder == [sessions[2].id, sessions[1].id, sessions[0].id])
    }

    @Test func ticketGroupingNestsWithPRUnionAndSuffixes() {
        let first = session("api", ticket: "XYZ-123", prs: ["https://gh/pr/1"], at: 0)
        let second = session("web", ticket: "XYZ-123", prs: ["https://gh/pr/2", "https://gh/pr/1"], at: 10)
        let loose = session("misc")
        let single = session("ops", ticket: "XYZ-9")
        let layout = SessionOrdering.layout(sessions: [loose, second, single, first], sort: .ticket, grouping: .ticket)

        let items = layout.sections[0].items
        guard case .ticket(let nine) = items[0], case .ticket(let group) = items[1],
              case .session(let entry) = items[2] else {
            Issue.record("unexpected items \(items)")
            return
        }
        #expect(nine.ticketID == "XYZ-9")
        #expect(nine.entries.map(\.ticketLabel) == ["XYZ-9"])
        #expect(group.ticketID == "XYZ-123")
        #expect(group.prURLs == ["https://gh/pr/1", "https://gh/pr/2"])
        #expect(group.entries.map(\.ticketLabel) == ["XYZ-123-A", "XYZ-123-B"])
        #expect(entry.session.id == loose.id)
        #expect(layout.visibleOrder == [single.id, first.id, second.id, loose.id])
    }

    @Test func visibleOrderSkipsCollapsedGroups() {
        let a = session("a", ticket: "T-1"), b = session("b", ticket: "T-1", at: 1)
        let c = session("c"), s = session("s", kind: .scratch)
        let collapsedTicket = SessionOrdering.layout(sessions: [a, b, c, s], sort: .ticket, grouping: .ticket,
                                                     collapsed: ["ticket:T-1"])
        #expect(collapsedTicket.visibleOrder == [c.id, s.id])

        let collapsedScratch = SessionOrdering.layout(sessions: [a, b, c, s], sort: .ticket, grouping: .none,
                                                      collapsed: [SessionOrdering.scratchSectionID])
        #expect(collapsedScratch.visibleOrder == [a.id, b.id, c.id])
        #expect(collapsedScratch.sections.last?.isCollapsed == true)
    }

    @Test func suffixesFollowCreationOrder() {
        let late = session("a", ticket: "Q-1", at: 20)
        let early = session("b", ticket: "Q-1", at: 0)
        let middle = session("c", ticket: "Q-1", at: 10)
        let other = session("d", ticket: "Q-2")
        let labels = TicketSuffixes.labels(for: [late, early, middle, other, session("e")])
        #expect(labels == [early.id: "Q-1-A", middle.id: "Q-1-B", late.id: "Q-1-C", other.id: "Q-2"])
        #expect(TicketSuffixes.letters(25) == "Z")
        #expect(TicketSuffixes.letters(26) == "AA")
    }
}
