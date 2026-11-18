import Foundation
import Testing
@testable import Switchboard

@MainActor
struct SessionStoreEventTests {
    private func makeStore() -> (SessionStore, Session) {
        let defaults = UserDefaults(suiteName: "SessionStoreEventTests-\(UUID())")!
        let store = SessionStore(settings: AppSettings(defaults: defaults))
        let session = Session(kind: .folder, folderPath: "/tmp/api", agent: .claudeCode)
        store.add(session, startTerminal: false)
        store.selectedID = nil
        store.isAppActive = { true }
        return (store, session)
    }

    @Test func sessionStartMapsAndRestartReplacesConversation() {
        let (store, session) = makeStore()
        store.handle(AgentEvent(rowID: session.id, kind: .sessionStarted, conversationID: "c-1"))
        store.handle(AgentEvent(rowID: session.id, kind: .statusLine("x"), conversationID: "c-1", title: "First"))
        #expect(store.sessions[0].agentConversationID == "c-1")
        #expect(store.sessions[0].title == "First")

        store.handle(AgentEvent(rowID: session.id, kind: .sessionStarted, conversationID: "c-2"))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].agentConversationID == "c-2")
        #expect(store.sessions[0].title == "api")
    }

    @Test func subagentEventsDoNotRemapConversation() {
        let (store, session) = makeStore()
        store.handle(AgentEvent(rowID: session.id, kind: .sessionStarted, conversationID: "c-1"))
        store.handle(AgentEvent(rowID: session.id, kind: .subagentStarted, conversationID: "other"))
        #expect(store.sessions[0].agentConversationID == "c-1")
    }

    @Test func unknownRowIsIgnored() {
        let (store, _) = makeStore()
        let before = store.sessions
        store.handle(AgentEvent(rowID: UUID(), kind: .turnFinished, conversationID: "c"))
        #expect(store.sessions == before)
    }

    @Test func finishedBadgesUnselectedRowUntilViewed() {
        let (store, session) = makeStore()
        store.handle(AgentEvent(rowID: session.id, kind: .turnFinished))
        #expect(store.sessions[0].workingState == .finished)
        #expect(store.sessions[0].hasBadge)

        store.selectedID = session.id
        #expect(store.sessions[0].workingState == .idle)
        #expect(!store.sessions[0].hasBadge)
    }

    @Test func selectedRowInFrontmostAppNeedsNoBadge() {
        let (store, session) = makeStore()
        store.selectedID = session.id
        store.handle(AgentEvent(rowID: session.id, kind: .turnFinished))
        #expect(store.sessions[0].workingState == .idle)
        #expect(!store.sessions[0].hasBadge)

        store.isAppActive = { false }
        store.handle(AgentEvent(rowID: session.id, kind: .needsInput))
        #expect(store.sessions[0].workingState == .needsInput)
        #expect(store.sessions[0].hasBadge)
    }

    @Test func statusLineModelIsShown() {
        let (store, session) = makeStore()
        store.handle(AgentEvent(rowID: session.id, kind: .statusLine("\u{1B}[36mOpus\u{1B}[0m\nctx 3%\n"), model: "Opus"))
        #expect(store.sessions[0].agentModel == "Opus")
    }
}

@MainActor
struct SetTicketTests {
    private func makeStore() -> (SessionStore, Session, Session) {
        let defaults = UserDefaults(suiteName: "SetTicketTests-\(UUID())")!
        let store = SessionStore(settings: AppSettings(defaults: defaults))
        var a = Session(kind: .folder, folderPath: "/tmp/a", agent: .claudeCode)
        a.ticketID = "ENG-1"
        a.ticketTitle = "First"
        var b = Session(kind: .folder, folderPath: "/tmp/b", agent: .claudeCode)
        b.ticketID = "ENG-2"
        store.add(a, startTerminal: false)
        store.add(b, startTerminal: false)
        return (store, a, b)
    }

    private func row(_ store: SessionStore, _ id: UUID) -> Session { store.sessions.first { $0.id == id }! }

    @Test func movesToAnotherTicketAndCopiesItsDetails() {
        let (store, a, b) = makeStore()
        #expect(store.setTicket("eng-1", for: b.id))
        #expect(row(store, b.id).ticketID == "ENG-1")
        #expect(row(store, b.id).ticketTitle == "First")
        #expect(row(store, b.id).ticketSetByUser)
        #expect(store.ticketIDs(excluding: a.id).isEmpty)
    }

    @Test func acceptsLinearURLAndRejectsJunk() {
        let (store, _, b) = makeStore()
        #expect(store.setTicket("https://linear.app/acme/issue/OPS-7/some-title", for: b.id))
        #expect(row(store, b.id).ticketID == "OPS-7")
        #expect(!store.setTicket("not a ticket", for: b.id))
        #expect(row(store, b.id).ticketID == "OPS-7")
    }

    @Test func removingStopsPromptsFromRetagging() {
        let (store, _, b) = makeStore()
        store.setTicket(nil, for: b.id)
        #expect(row(store, b.id).ticketID == nil)
        #expect(TicketTagging.ticket(toTag: row(store, b.id), prompt: "work on ENG-9", teamKeys: ["ENG"]) == nil)
    }

    @Test func manualFlagSurvivesPersistence() throws {
        var s = Session(kind: .folder, folderPath: "/tmp/x", agent: .claudeCode)
        s.ticketSetByUser = true
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        #expect(decoded.ticketSetByUser)
    }
}
