import Foundation

/// Claude Code hooks and status line.
enum ClaudeEvents {
    static func kind(event: String, json: [String: Any], trailingText: String) -> AgentEvent.Kind? {
        switch event {
        case "SessionStart": return .sessionStarted
        case "UserPromptSubmit": return .promptSubmitted
        case "PreToolUse", "PostToolUse", "PostToolUseFailure": return .toolActivity
        case "PermissionRequest": return .needsInput
        case "SubagentStart": return .subagentStarted
        case "SubagentStop": return .subagentStopped
        case "Stop", "StopFailure": return .turnFinished
        case "SessionEnd": return .sessionEnded
        case "statusline": return .statusLine(trailingText)
        case "Notification":
            switch json["notification_type"] as? String {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                return .needsInput
            case "idle_prompt":
                return .idleReminder
            default:
                return .info
            }
        default: return nil
        }
    }
}

/// Codex hooks plus its `notify` program. Hooks run only once the user has
/// trusted them in Codex's `/hooks`; until then only `notify` arrives, which
/// gives mapping and "finished" but no working or needs-input states.
enum CodexEvents {
    static func kind(event: String, json: [String: Any]) -> AgentEvent.Kind? {
        switch event {
        case "SessionStart": return .sessionStarted
        case "UserPromptSubmit": return .promptSubmitted
        case "PreToolUse", "PostToolUse": return .toolActivity
        case "PermissionRequest": return .needsInput
        case "SubagentStart": return .subagentStarted
        case "SubagentStop": return .subagentStopped
        case "Stop": return .turnFinished
        case "SessionEnd": return .sessionEnded
        case "notify":
            return json["type"] as? String == "agent-turn-complete" ? .turnFinished : nil
        default: return nil
        }
    }
}

/// Gemini CLI hooks, from its documentation. It has no sub-agent events.
enum GeminiEvents {
    static func kind(event: String, json: [String: Any]) -> AgentEvent.Kind? {
        switch event {
        case "SessionStart": return .sessionStarted
        case "BeforeAgent": return .promptSubmitted
        case "BeforeTool", "AfterTool": return .toolActivity
        case "Notification":
            return json["notification_type"] as? String == "ToolPermission" ? .needsInput : .info
        case "AfterAgent": return .turnFinished
        case "SessionEnd": return .sessionEnded
        default: return nil
        }
    }
}
