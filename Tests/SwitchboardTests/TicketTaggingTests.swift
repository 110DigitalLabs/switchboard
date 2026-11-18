import Foundation
import Testing
@testable import Switchboard

@MainActor
struct TicketTaggingTests {
    @Test func tagsOnlyUntaggedSessionsWithFirstValidMention() {
        let untagged = TicketTestSupport.session()
        let keys: Set<String> = ["ENG", "OPS"]
        #expect(TicketTagging.ticket(toTag: untagged, prompt: "fix UTF-8 for ops-4 then ENG-2", teamKeys: keys) == "OPS-4")
        #expect(TicketTagging.ticket(toTag: untagged, prompt: "nothing here", teamKeys: keys) == nil)
        #expect(TicketTagging.ticket(toTag: untagged, prompt: nil, teamKeys: keys) == nil)
        #expect(TicketTagging.ticket(toTag: untagged, prompt: "ENG-1", teamKeys: []) == nil)
        let tagged = TicketTestSupport.session(ticket: "ENG-9")
        #expect(TicketTagging.ticket(toTag: tagged, prompt: "now ENG-1", teamKeys: keys) == nil)
    }

    @Test func decodersCarryPromptText() {
        let id = UUID()
        func decode(_ agent: String, _ event: String) -> AgentEvent? {
            AgentEventDecoder.decode(HookMessage(agent: agent, event: event, rowID: id,
                                                 payload: Data(#"{"prompt":"work on ENG-3"}"#.utf8)))
        }
        #expect(decode("claude", "UserPromptSubmit")?.prompt == "work on ENG-3")
        #expect(decode("codex", "UserPromptSubmit")?.prompt == "work on ENG-3")
        #expect(decode("gemini", "BeforeAgent")?.prompt == "work on ENG-3")
        #expect(decode("claude", "Stop")?.prompt == nil)
    }

    @Test func promptEventTagsInPlaceAndLoadsDetails() async throws {
        let service = FakeLinearService(issues: [TicketTestSupport.issue("ENG-3", title: "Fetched", project: "Core")])
        let source = StubTicketSource(teamKeys: ["ENG"], service: service)
        let store = TicketTestSupport.store()
        store.ticketSource = source
        let session = TicketTestSupport.session(.folder, path: "/tmp/api")
        store.add(session, startTerminal: false)

        store.handle(AgentEvent(rowID: session.id, kind: .promptSubmitted, conversationID: "c1",
                                prompt: "let's work on eng-3"))
        #expect(store.sessions[0].ticketID == "ENG-3")
        #expect(store.sessions[0].kind == .folder)
        #expect(store.sessions[0].folderPath == "/tmp/api")

        for _ in 0..<50 where store.sessions[0].ticketTitle == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.sessions[0].ticketTitle == "Fetched")
        #expect(store.sessions[0].linearProjectName == "Core")

        store.handle(AgentEvent(rowID: session.id, kind: .promptSubmitted, conversationID: "c1",
                                prompt: "and ENG-4 too"))
        #expect(store.sessions[0].ticketID == "ENG-3")
    }

    @Test func offlineStillTagsWithoutDetails() {
        let store = TicketTestSupport.store()
        let source = StubTicketSource(teamKeys: ["ENG"], isConnected: false)
        store.ticketSource = source // weak
        let session = TicketTestSupport.session()
        store.add(session, startTerminal: false)
        store.handle(AgentEvent(rowID: session.id, kind: .promptSubmitted, prompt: "ENG-8 please"))
        #expect(store.sessions[0].ticketID == "ENG-8")
        #expect(store.sessions[0].ticketTitle == nil)
        withExtendedLifetime(source) {}
    }
}
