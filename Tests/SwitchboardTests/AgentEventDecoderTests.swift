import Foundation
import Testing
@testable import Switchboard

struct AgentEventDecoderTests {
    private let row = UUID()

    private func decode(_ agent: String, _ event: String, _ json: String, trailing: String = "") -> AgentEvent? {
        AgentEventDecoder.decode(HookMessage(agent: agent, event: event, rowID: row,
                                             payload: Data(json.utf8), trailingText: trailing))
    }

    @Test func claudeSessionStartMapsConversationAndModel() throws {
        let event = try #require(decode("claude", "SessionStart", """
            {"session_id":"c-1","transcript_path":"/t.jsonl","cwd":"/r","hook_event_name":"SessionStart",
             "source":"startup","model":"claude-opus-4"}
            """))
        #expect(event.rowID == row)
        #expect(event.kind == .sessionStarted)
        #expect(event.conversationID == "c-1")
        #expect(event.model == "claude-opus-4")
        #expect(event.transcriptPath == "/t.jsonl")
    }

    @Test func claudeNotificationKinds() {
        func kind(_ type: String) -> AgentEvent.Kind? {
            decode("claude", "Notification", #"{"session_id":"c","notification_type":"\#(type)"}"#)?.kind
        }
        #expect(kind("permission_prompt") == .needsInput)
        #expect(kind("elicitation_dialog") == .needsInput)
        #expect(kind("idle_prompt") == .idleReminder)
        #expect(kind("auth_success") == .info)
    }

    @Test func claudeHookEventsMapToKinds() {
        #expect(decode("claude", "UserPromptSubmit", "{}")?.kind == .promptSubmitted)
        #expect(decode("claude", "PreToolUse", "{}")?.kind == .toolActivity)
        #expect(decode("claude", "PermissionRequest", "{}")?.kind == .needsInput)
        #expect(decode("claude", "SubagentStart", #"{"agent_id":"a"}"#)?.kind == .subagentStarted)
        #expect(decode("claude", "SubagentStop", "{}")?.kind == .subagentStopped)
        #expect(decode("claude", "Stop", "{}")?.kind == .turnFinished)
        #expect(decode("claude", "SessionEnd", "{}")?.kind == .sessionEnded)
        #expect(decode("claude", "SomethingNew", "{}") == nil)
    }

    @Test func claudeStatusLineCarriesTextTitleAndDisplayModel() throws {
        let event = try #require(decode("claude", "statusline", """
            {"session_id":"c-1","session_name":"Fix login","model":{"id":"claude-opus-4","display_name":"Opus"}}
            """, trailing: "\u{1B}[36mOpus\u{1B}[0m"))
        #expect(event.kind == .statusLine("\u{1B}[36mOpus\u{1B}[0m"))
        #expect(event.title == "Fix login")
        #expect(event.model == "Opus")
        #expect(event.conversationID == "c-1")
    }

    @Test func codexHooksAndNotify() throws {
        let start = try #require(decode("codex", "SessionStart", #"{"session_id":"x-1","model":"gpt-5","source":"startup"}"#))
        #expect(start.kind == .sessionStarted)
        #expect(start.conversationID == "x-1")
        #expect(start.model == "gpt-5")
        #expect(decode("codex", "PermissionRequest", "{}")?.kind == .needsInput)

        let notify = try #require(decode("codex", "notify", """
            {"type":"agent-turn-complete","thread-id":"x-2","turn-id":"t","cwd":"/r",
             "input-messages":["hi"],"last-assistant-message":"ok"}
            """))
        #expect(notify.kind == .turnFinished)
        #expect(notify.conversationID == "x-2")
        #expect(decode("codex", "notify", #"{"type":"something-else"}"#) == nil)
    }

    @Test func geminiHooks() {
        #expect(decode("gemini", "SessionStart", #"{"session_id":"g-1"}"#)?.conversationID == "g-1")
        #expect(decode("gemini", "BeforeAgent", "{}")?.kind == .promptSubmitted)
        #expect(decode("gemini", "Notification", #"{"notification_type":"ToolPermission"}"#)?.kind == .needsInput)
        #expect(decode("gemini", "AfterAgent", "{}")?.kind == .turnFinished)
    }

    @Test func unknownAgentsAndBadJSONAreHandled() {
        #expect(decode("cursor", "stop", "{}") == nil)
        #expect(decode("claude", "Stop", "not json")?.kind == .turnFinished)
    }
}
