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
