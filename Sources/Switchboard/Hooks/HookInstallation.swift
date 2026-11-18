import Foundation

/// Where Switchboard's hook helper and per-agent settings live, and how a
/// session's shell and launch command pick them up. Nothing here touches the
/// user's own agent configuration; every agent gets Switchboard's hooks only
/// for launches made from a Switchboard terminal.
struct HookInstallation: Sendable, Equatable {
    var helperPath: String
    var socketPath: String
    var claudeSettingsPath: String
    var geminiSettingsPath: String
    /// Codex has a single `notify` program; leave it alone if the user set one.
    var injectCodexNotify: Bool
    /// Gemini's system-defaults file is redirected only if the user has none.
    var injectGeminiDefaults: Bool

    enum Key {
        static let socket = "SWITCHBOARD_SOCKET"
        static let helper = "SWITCHBOARD_HOOK"
        static let claudeSettings = "SWITCHBOARD_CLAUDE_SETTINGS"
        static let codexHooks = "SWITCHBOARD_CODEX_HOOKS"
        static let codexNotify = "SWITCHBOARD_CODEX_NOTIFY"
        static let geminiDefaults = "GEMINI_CLI_SYSTEM_DEFAULTS_PATH"
    }

    /// Variables added to a session's shell. Launch commands refer to these
    /// rather than spelling out paths, so the typed line stays short and
    /// "Application Support" never needs quoting in it.
    func environment(for agent: Agent) -> [String: String] {
        var env = [
            Key.socket: socketPath,
            Key.helper: helperPath,
        ]
        switch agent {
        case .claudeCode:
            env[Key.claudeSettings] = claudeSettingsPath
        case .codex:
            env[Key.codexHooks] = CodexHookConfig.hooksOverride
            if injectCodexNotify { env[Key.codexNotify] = CodexHookConfig.notifyOverride }
        case .geminiCLI:
            if injectGeminiDefaults { env[Key.geminiDefaults] = geminiSettingsPath }
        case .cursorAgent:
            break
        }
        return env
    }

    /// Arguments that load Switchboard's hooks, placed right after the
    /// executable. Each references a variable from `environment(for:)`.
    func launchArguments(for agent: Agent) -> [String] {
        switch agent {
        case .claudeCode:
            ["--settings", "\"$\(Key.claudeSettings)\""]
        case .codex:
            ["-c", "\"$\(Key.codexHooks)\""]
                + (injectCodexNotify ? ["-c", "\"$\(Key.codexNotify)\""] : [])
        case .geminiCLI, .cursorAgent:
            // Gemini picks its hooks up from the environment; Cursor's agent
            // CLI has no per-launch way to add hooks (see CursorHookConfig).
            []
        }
    }
}
