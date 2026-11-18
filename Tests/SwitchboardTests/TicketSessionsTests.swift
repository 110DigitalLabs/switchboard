import Foundation
import Testing
@testable import Switchboard

struct TicketSessionsTests {
    @Test func existingSessionsAreMatchedCaseInsensitivelyInCreationOrder() {
        let b = TicketTestSupport.session(ticket: "ENG-5", created: 20)
        let a = TicketTestSupport.session(ticket: "eng-5", created: 10)
        let none = TicketTestSupport.session(created: 0)
        #expect(TicketSessions.existing(for: "ENG-5", in: [b, none, a]).map(\.id) == [a.id, b.id])
        #expect(TicketSessions.existing(for: "ENG-6", in: [a, b]).isEmpty)
    }

    @Test func assignedListSkipsTicketsWithSessions() {
        let issues = ["ENG-1", "ENG-2", "ENG-3"].map { TicketTestSupport.issue($0) }
        let sessions = [TicketTestSupport.session(ticket: "ENG-2")]
        #expect(TicketSessions.unstarted(issues, sessions: sessions).map(\.identifier) == ["ENG-1", "ENG-3"])
    }

    @Test func suffixesNumberSessionsOnOneTicket() {
        let first = TicketTestSupport.session(.temp, ticket: "ENG-5", created: 10)
        let second = TicketSessions.sibling(of: first, now: Date(timeIntervalSince1970: 20))
        let solo = TicketTestSupport.session(ticket: "ENG-9")
        let labels = TicketSuffixes.labels(for: [second, solo, first])
        #expect(labels[first.id] == "ENG-5-A")
        #expect(labels[second.id] == "ENG-5-B")
        #expect(labels[solo.id] == "ENG-9")
    }

    @Test func siblingKeepsFolderKindTicketAndAgent() {
        var worktree = TicketTestSupport.session(.worktree, path: "/home/api", ticket: "ENG-5", agent: .codex)
        worktree.ticketTitle = "Title"
        worktree.linearProjectName = "Proj"
        worktree.agentConversationID = "conv"
        worktree.agentTitle = "Agent title"
        let sibling = TicketSessions.sibling(of: worktree)
        #expect(sibling.id != worktree.id)
        #expect(sibling.kind == .worktree)
        #expect(sibling.folderPath == "/home/api")
        #expect(sibling.agent == .codex)
        #expect(sibling.ticketID == "ENG-5" && sibling.ticketTitle == "Title" && sibling.linearProjectName == "Proj")
        #expect(sibling.agentConversationID == nil && sibling.agentTitle == nil)

        let temp = TicketSessions.sibling(of: TicketTestSupport.session(.temp, path: "/home/tickets/ENG-5"))
        #expect(temp.kind == .temp && temp.folderPath == "/home/tickets/ENG-5")
    }

    @Test func newSessionFollowsDestination() {
        let issue = TicketTestSupport.issue("ENG-5", title: "Fix it", project: "Core")
        let temp = TicketSessions.newSession(for: issue, destination: .tempFolder, agent: .claudeCode,
                                             tempFolder: URL(fileURLWithPath: "/home/tickets/ENG-5"))
        #expect(temp.kind == .temp && temp.folderPath == "/home/tickets/ENG-5")
        #expect(temp.ticketID == "ENG-5" && temp.ticketTitle == "Fix it" && temp.linearProjectName == "Core")
        #expect(temp.title == "ENG-5")

        let repo = Repo(url: URL(fileURLWithPath: "/home/api"), relativePath: "api")
        let inRepo = TicketSessions.newSession(for: issue, destination: .repo(repo), agent: .claudeCode,
                                               tempFolder: URL(fileURLWithPath: "/unused"), isRepo: { _ in true })
        #expect(inRepo.kind == .worktree && inRepo.folderPath == "/home/api")
        let gemini = TicketSessions.newSession(for: issue, destination: .repo(repo), agent: .geminiCLI,
                                               tempFolder: URL(fileURLWithPath: "/unused"), isRepo: { _ in true })
        #expect(gemini.kind == .folder)
    }

    @Test func draftsAreSingleLineAndNotSubmitted() {
        var temp = TicketTestSupport.session(.temp, ticket: "ENG-5")
        temp.ticketTitle = "Fix\nit"
        let planning = TicketPrompts.draft(for: temp)
        #expect(planning == "Let's plan ENG-5 (Fix it). The ticket is in TICKET.md. ")
        let worktree = TicketTestSupport.session(.worktree, ticket: "ENG-5")
        #expect(TicketPrompts.draft(for: worktree) == "Let's work on ENG-5. ")
        #expect(TicketPrompts.draft(for: TicketTestSupport.session()) == nil)
        #expect(planning?.contains("\n") == false)
    }

    @Test func ticketTitleDoesNotOverrideDisplayPriority() {
        var session = TicketTestSupport.session(path: "/x/api", ticket: "ENG-5")
        session.ticketTitle = "Ticket title"
        #expect(session.title == "ENG-5")
        session.agentTitle = "Agent"
        #expect(session.title == "Agent")
    }
}

struct TicketTitlePersistenceTests {
    @Test func ticketTitleRoundTrips() throws {
        var session = TicketTestSupport.session(.temp, path: "/t", ticket: "ENG-1")
        session.ticketTitle = "Title"
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded.ticketTitle == "Title" && decoded.ticketID == "ENG-1")
    }
}
