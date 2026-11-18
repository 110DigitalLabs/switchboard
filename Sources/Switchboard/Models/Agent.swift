import Foundation

/// A coding-agent CLI that Switchboard can launch in a session's terminal.
enum Agent: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case geminiCLI
    case cursorAgent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .cursorAgent: "Cursor Agent"
        }
    }

    var executable: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .cursorAgent: "cursor-agent"
        }
    }

    /// The agent's own flag for starting in a fresh git worktree, or nil when
    /// the agent has no verified worktree convention. Gemini CLI and Cursor's
    /// agent CLI document no such flag, so Switchboard starts them plainly in
    /// the repo folder rather than inventing a worktree layout for them.
    var worktreeFlag: String? {
        switch self {
        case .claudeCode: "-w"
        case .codex: "--worktree"
        case .geminiCLI, .cursorAgent: nil
        }
    }

    var supportsWorktree: Bool { worktreeFlag != nil }

    /// The command line typed into the session's shell to start the agent.
    func launchCommand(for kind: SessionKind) -> String {
        if kind == .worktree, let flag = worktreeFlag {
            return "\(executable) \(flag)"
        }
        return executable
    }
}
