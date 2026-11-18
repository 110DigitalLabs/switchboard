import Foundation

/// Builds how a session's login shell is launched.
enum ShellEnvironment {
    static let rowIDKey = "SWITCHBOARD_ROW_ID"

    /// Variables an agent sets for its own session and children. When
    /// Switchboard is launched from inside such a session they are inherited,
    /// and an agent started with them believes it is a sub-session: Claude Code
    /// then stops saving transcripts and reuses the parent's messaging socket.
    /// User configuration such as CLAUDE_CODE_USE_BEDROCK is kept.
    static let inheritedSessionKeys: Set<String> = [
        "CLAUDECODE",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_CHILD_NOTES_DIR",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_EXECPATH",
        "CLAUDE_CODE_MESSAGING_SOCKET",
        "CLAUDE_CODE_MESSAGING_TOKEN",
        "CLAUDE_CODE_SESSION_ATTENDED",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_SSE_PORT",
    ]

    /// `environment` without another session's markers or a stale row ID.
    static func scrubbed(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in key != rowIDKey && !inheritedSessionKeys.contains(key) }
    }

    /// The user's `$SHELL`, falling back to zsh when unset or not executable.
    static func loginShell(from environment: [String: String]) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty,
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// argv[0] with a leading dash, which makes the shell a login shell.
    static func loginExecName(for shell: String) -> String {
        "-" + URL(fileURLWithPath: shell).lastPathComponent
    }

    static func variables(base: [String: String], rowID: UUID,
                          extra: [String: String] = [:]) -> [String: String] {
        var env = scrubbed(base).merging(extra) { _, new in new }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"]?.isEmpty ?? true {
            env["LANG"] = "en_US.UTF-8"
        }
        env[rowIDKey] = rowID.uuidString
        return env
    }

    static func pairs(_ env: [String: String]) -> [String] {
        env.map { "\($0.key)=\($0.value)" }.sorted()
    }
}
