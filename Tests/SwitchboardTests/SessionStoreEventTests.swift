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
