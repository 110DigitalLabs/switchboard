import Foundation

/// Gemini CLI has no per-launch settings flag, but it reads a "system
/// defaults" settings file from `$GEMINI_CLI_SYSTEM_DEFAULTS_PATH`. That layer
/// has the lowest precedence, so it never overrides anything the user set.
/// Implemented from Gemini's documentation; not verified against a real run.
///
/// Model: Gemini reports it only inside BeforeModel's full `llm_request`,
/// which carries the whole conversation on every model call, so it is not
/// hooked and the model stays unknown.
enum GeminiHookConfig {
    static let events = [
        "SessionStart", "BeforeAgent", "BeforeTool", "AfterTool",
        "Notification", "AfterAgent", "SessionEnd",
    ]

    static let systemDefaultsPath = "/Library/Application Support/GeminiCli/system-defaults.json"

    static func settings(helperPath: String) -> [String: Any] {
        let helper = ShellQuote.quote(helperPath)
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [[
                "hooks": [[
                    "type": "command",
                    "name": "switchboard",
                    "command": "\(helper) gemini \(event)",
                    "timeout": 5000,
                ] as [String: Any]],
            ]]
        }
        return ["hooks": hooks]
    }
}
