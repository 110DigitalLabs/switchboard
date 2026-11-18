import Foundation

/// Builds how a session's login shell is launched.
enum ShellEnvironment {
    static let rowIDKey = "SWITCHBOARD_ROW_ID"

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
        var env = base.merging(extra) { _, new in new }
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
