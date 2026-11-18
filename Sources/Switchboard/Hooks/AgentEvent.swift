import Foundation

/// An agent hook event, normalized across agents.
struct AgentEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A new or resumed conversation began in the row's terminal.
        case sessionStarted
        case promptSubmitted
        case toolActivity
        case subagentStarted
        case subagentStopped
        case needsInput
        /// Claude's reminder that a finished turn is still waiting on the user.
        case idleReminder
        case turnFinished
        case sessionEnded
        case statusLine(String)
        /// Carries only metadata (IDs, model, title).
        case info
    }

    var rowID: UUID
    var kind: Kind
    var conversationID: String?
    var model: String?
    var title: String?
    var transcriptPath: String?
    /// The agent's working directory (a worktree, for worktree sessions).
    var cwd: String?

    init(rowID: UUID, kind: Kind, conversationID: String? = nil, model: String? = nil,
         title: String? = nil, transcriptPath: String? = nil, cwd: String? = nil) {
        self.rowID = rowID
        self.kind = kind
        self.conversationID = conversationID
        self.model = model
        self.title = title
        self.transcriptPath = transcriptPath
        self.cwd = cwd
    }
}

enum AgentEventDecoder {
    /// Returns nil for messages that are malformed or carry nothing useful.
    static func decode(_ message: HookMessage) -> AgentEvent? {
        let json = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any] ?? [:]
        let kind: AgentEvent.Kind?
        switch message.agent {
        case "claude": kind = ClaudeEvents.kind(event: message.event, json: json, trailingText: message.trailingText)
        case "codex": kind = CodexEvents.kind(event: message.event, json: json)
        case "gemini": kind = GeminiEvents.kind(event: message.event, json: json)
        // Cursor's agent CLI reads hooks only from ~/.cursor/hooks.json or the
        // project's .cursor/hooks.json and has no per-launch override, so
        // Switchboard installs nothing for it and its rows stay idle.
        default: kind = nil
        }
        guard let kind else { return nil }
        return AgentEvent(
            rowID: message.rowID,
            kind: kind,
            conversationID: string(json, "session_id") ?? string(json, "thread-id"),
            model: model(in: json),
            title: string(json, "session_name"),
            transcriptPath: string(json, "transcript_path"),
            cwd: string(json, "cwd")
        )
    }

    /// `model` is a string in hook payloads and `{id, display_name}` in
    /// Claude's status line.
    private static func model(in json: [String: Any]) -> String? {
        if let model = json["model"] as? [String: Any] {
            return string(model, "display_name") ?? string(model, "id")
        }
        return string(json, "model")
    }

    static func string(_ json: [String: Any], _ key: String) -> String? {
        guard let value = json[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
