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

    /// Claude's and Gemini's SessionStart hooks always run; Codex runs its
    /// hooks only once trusted, and Cursor's agent gets none.
    var reportsSessionStartReliably: Bool { self == .claudeCode || self == .geminiCLI }

    /// The command line typed into the session's shell to start the agent,
    /// with Switchboard's hooks loaded when they are installed. An initial
    /// prompt is submitted by the agent as its first message.
    func launchCommand(for kind: SessionKind, hooks: HookInstallation? = nil,
                       options: AgentLaunchOptions = AgentLaunchOptions()) -> String {
        var words = [executable]
        words += hooks?.launchArguments(for: self) ?? []
        if let prompt = options.prompt, !prompt.isEmpty {
            // Before the worktree flag: Claude's `-w [name]` would take a
            // following word as the worktree's name.
            words += promptArguments(ShellQuote.quote(prompt))
        }
        if options.planMode, let plan = planModeArguments {
            words += plan
        }
        if kind == .worktree, let flag = worktreeFlag {
            words.append(flag)
        }
        return words.joined(separator: " ")
    }

    /// The agent's own read-only planning mode, where it has one.
    var planModeArguments: [String]? {
        switch self {
        case .claudeCode: ["--permission-mode", "plan"]
        case .codex, .geminiCLI, .cursorAgent: nil
        }
    }

    /// How each CLI takes a first prompt and stays interactive: a positional
    /// argument, except Gemini, where a positional prompt runs headless.
    private func promptArguments(_ quoted: String) -> [String] {
        switch self {
        case .geminiCLI: ["-i", quoted]
        case .claudeCode, .codex, .cursorAgent: [quoted]
        }
    }
}

/// Extras for a fresh agent launch.
struct AgentLaunchOptions: Equatable, Sendable {
    /// Start in the agent's planning mode (Claude only).
    var planMode = false
    /// Submitted as the agent's first message.
    var prompt: String?
}
