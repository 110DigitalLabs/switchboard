import Foundation
import Testing
@testable import Switchboard

struct HookPullRequestTests {
    private let row = UUID()

    private func event(_ agent: String, _ name: String, _ json: String) -> AgentEvent? {
        AgentEventDecoder.decode(HookMessage(agent: agent, event: name, rowID: row, payload: Data(json.utf8)))
    }

    @Test func claudeBashPostToolUseResponseURL() {
        let json = """
        {"session_id":"c1","hook_event_name":"PostToolUse","tool_name":"Bash",
         "tool_input":{"command":"gh pr create --fill","description":"Open a PR"},
         "tool_response":{"stdout":"Creating pull request for feature into main in acme/api\\n\\nhttps://github.com/acme/api/pull/42\\n","stderr":"","interrupted":false,"isImage":false}}
        """
        #expect(event("claude", "PostToolUse", json)?.prURLs == ["https://github.com/acme/api/pull/42"])
    }

    @Test func urlInToolInputCountsAndIsCanonicalised() {
        let json = """
        {"tool_name":"Bash","tool_input":{"command":"gh pr view https://github.com/Acme/api/pull/7/files"},
         "tool_response":{"stdout":"title: x\\nurl: https://github.com/Acme/api/pull/7\\n"}}
        """
        #expect(event("claude", "PostToolUse", json)?.prURLs == ["https://github.com/Acme/api/pull/7"])
    }

    @Test func codexAndGeminiShapes() {
        let codex = """
        {"session_id":"x","tool_name":"shell","tool_input":{"command":["bash","-lc","gh pr create"]},
         "tool_response":"https://github.com/a/b/pull/3"}
        """
        #expect(event("codex", "PostToolUse", codex)?.prURLs == ["https://github.com/a/b/pull/3"])
        let gemini = """
        {"tool_name":"run_shell_command","tool_input":{"command":"gh pr create"},
         "tool_response":{"llmContent":"Output: https://github.com/a/b/pull/4","returnDisplay":"https://github.com/a/b/pull/4"}}
        """
        #expect(event("gemini", "AfterTool", gemini)?.prURLs == ["https://github.com/a/b/pull/4"])
    }

    @Test func otherEventsAndNonPRLinksAreIgnored() {
        let json = """
        {"tool_input":{"command":"gh pr create"},"tool_response":{"stdout":"https://github.com/a/b/pull/5"}}
        """
        #expect(event("claude", "PreToolUse", json)?.prURLs == [])
        let issue = """
        {"tool_input":{"command":"x"},"tool_response":{"stdout":"https://github.com/a/b/issues/5 https://github.com/a/b/pull/abc https://gitlab.com/a/b/pull/1"}}
        """
        #expect(event("claude", "PostToolUse", issue)?.prURLs == [])
        #expect(event("claude", "UserPromptSubmit", #"{"prompt":"see https://github.com/a/b/pull/9"}"#)?.prURLs == [])
    }

    @MainActor
    @Test func storeLinksHookPRsOnceAndAsksForARefresh() {
        let store = TicketTestSupport.store()
        let session = Session(kind: .folder, folderPath: "/tmp/api", agent: .claudeCode)
        store.add(session, startTerminal: false)
        var refreshes = 0
        store.onPullRequestSourcesChanged = { refreshes += 1 }
        let url = "https://github.com/acme/api/pull/42"
        store.handle(AgentEvent(rowID: session.id, kind: .toolActivity, prURLs: [url]))
        store.handle(AgentEvent(rowID: session.id, kind: .toolActivity, prURLs: [url + "/files"]))
        #expect(store.sessions[0].prURLs == [url])
        #expect(refreshes == 1)
    }
}
