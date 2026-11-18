import Foundation

/// Switchboard's settings file for Claude Code, loaded per launch with
/// `claude --settings <file>`. Hooks from `--settings` are added to the user's
/// own hooks rather than replacing them. `statusLine` is a single value, so
/// ours wins over the user's; the helper runs the user's command itself and
/// prints its output unchanged.
enum ClaudeHookConfig {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "SubagentStart", "SubagentStop",
        "Stop", "StopFailure", "SessionEnd",
    ]

    /// - Parameter userStatusLine: the `statusLine` object from the user's
    ///   `~/.claude/settings.json`, whose layout keys are carried over.
    static func settings(helperPath: String, userStatusLine: [String: Any]?) -> [String: Any] {
        let helper = ShellQuote.quote(helperPath)
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [[
                "hooks": [[
                    "type": "command",
                    "command": "\(helper) claude \(event)",
                    "timeout": 5,
                ] as [String: Any]],
            ]]
        }
        var statusLine: [String: Any] = [
            "type": "command",
            "command": "\(helper) claude statusline",
        ]
        for key in ["padding", "refreshInterval"] {
            if let value = userStatusLine?[key] { statusLine[key] = value }
        }
        return ["hooks": hooks, "statusLine": statusLine]
    }

    static func userStatusLine(configDirectory: URL) -> [String: Any]? {
        let url = configDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["statusLine"] as? [String: Any]
    }
}
