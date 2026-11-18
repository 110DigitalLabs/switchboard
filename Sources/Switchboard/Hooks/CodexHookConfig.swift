import Foundation

/// Codex config overrides passed per launch as `codex -c <key=value>`.
///
/// Two channels, because they behave differently:
/// - `notify` runs on every finished turn with no trust step, and carries the
///   thread ID, so mapping and "finished" always work.
/// - `hooks` give the richer states (working, needs input, sub-agents) but
///   Codex runs non-managed hooks only after the user trusts them once in
///   `/hooks`. Trust is keyed by the hook's hash, so the commands refer to
///   `$SWITCHBOARD_HOOK` instead of a path: the hash then never changes.
///
/// `-c` layers over `~/.codex/config.toml`; an event the user also hooks in
/// config.toml gets ours for this launch, while `hooks.json` files still load.
enum CodexHookConfig {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
        "SubagentStart", "SubagentStop", "Stop", "SessionEnd",
    ]

    static var hooksOverride: String {
        let entries = events.map { event in
            "\(event)=[{hooks=[{type=\"command\",command=\"\\\"$SWITCHBOARD_HOOK\\\" codex \(event)\",timeout=5}]}]"
        }
        return "hooks={\(entries.joined(separator: ","))}"
    }

    /// Codex appends the JSON payload as the last argument; `sh -c` sees it as $1.
    static let notifyOverride =
        #"notify=["/bin/sh","-c","exec \"$SWITCHBOARD_HOOK\" codex notify \"$1\"","switchboard-hook"]"#

    /// True when the user's config.toml sets its own top-level `notify`.
    static func userHasNotify(codexHome: URL) -> Bool {
        let url = codexHome.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { return false } // past the top-level keys
            if trimmed.hasPrefix("notify"),
               trimmed.dropFirst("notify".count).trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                return true
            }
        }
        return false
    }
}
