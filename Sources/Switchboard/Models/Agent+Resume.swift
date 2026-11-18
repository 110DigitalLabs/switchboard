import Foundation

extension Agent {
    /// The agent's own command for reopening a conversation by ID, with
    /// Switchboard's hooks loaded exactly as for a fresh launch. Syntax from
    /// each CLI's `--help` / docs:
    /// - `claude --resume <id>`
    /// - `codex resume <id>` (a subcommand; it takes `-c` overrides itself)
    /// - `gemini --resume <id>`
    /// - `cursor-agent --resume <id>`
    func resumeCommand(conversationID: String, hooks: HookInstallation? = nil) -> String {
        let hookArguments = hooks?.launchArguments(for: self) ?? []
        let id = ShellQuote.quoteIfNeeded(conversationID)
        let words: [String]
        switch self {
        case .codex:
            words = [executable, "resume"] + hookArguments + [id]
        case .claudeCode, .geminiCLI, .cursorAgent:
            words = [executable] + hookArguments + ["--resume", id]
        }
        return words.joined(separator: " ")
    }
}
