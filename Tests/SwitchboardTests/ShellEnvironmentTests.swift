import Foundation
import Testing
@testable import Switchboard

struct ShellEnvironmentTests {
    @Test func setsTerminalVariablesAndRowID() {
        let id = UUID()
        let env = ShellEnvironment.variables(base: ["PATH": "/bin", "TERM": "dumb"], rowID: id)
        #expect(env["PATH"] == "/bin")
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["LANG"] == "en_US.UTF-8")
        #expect(env["SWITCHBOARD_ROW_ID"] == id.uuidString)
    }

    @Test func dropsInheritedAgentSessionMarkers() {
        let base = [
            "PATH": "/bin",
            "CLAUDECODE": "1",
            "CLAUDE_CODE_CHILD_SESSION": "1",
            "CLAUDE_CODE_SESSION_ID": "parent",
            "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/sock",
            "CLAUDE_CODE_USE_BEDROCK": "1",
            "SWITCHBOARD_ROW_ID": "stale",
        ]
        let id = UUID()
        let env = ShellEnvironment.variables(base: base, rowID: id)
        #expect(env["CLAUDECODE"] == nil)
        #expect(env["CLAUDE_CODE_CHILD_SESSION"] == nil)
        #expect(env["CLAUDE_CODE_SESSION_ID"] == nil)
        #expect(env["CLAUDE_CODE_MESSAGING_SOCKET"] == nil)
        #expect(env["CLAUDE_CODE_USE_BEDROCK"] == "1")
        #expect(env["PATH"] == "/bin")
        #expect(env["SWITCHBOARD_ROW_ID"] == id.uuidString)
        #expect(ShellEnvironment.scrubbed(base)["SWITCHBOARD_ROW_ID"] == nil)
    }

    @Test func keepsExistingLang() {
        let env = ShellEnvironment.variables(base: ["LANG": "de_DE.UTF-8"], rowID: UUID())
        #expect(env["LANG"] == "de_DE.UTF-8")
    }

    @Test func loginShellFallsBackToZsh() {
        #expect(ShellEnvironment.loginShell(from: [:]) == "/bin/zsh")
        #expect(ShellEnvironment.loginShell(from: ["SHELL": "/no/such/shell"]) == "/bin/zsh")
        #expect(ShellEnvironment.loginShell(from: ["SHELL": "/bin/bash"]) == "/bin/bash")
        #expect(ShellEnvironment.loginExecName(for: "/opt/homebrew/bin/fish") == "-fish")
    }

    @Test func scratchFolderNameIsTimestamp() {
        let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00:00 UTC
        #expect(ScratchFolder.name(for: date, timeZone: TimeZone(identifier: "UTC")!) == "20260101-000000")
    }
}
