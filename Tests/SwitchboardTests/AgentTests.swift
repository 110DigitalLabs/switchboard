import Testing
import Foundation
@testable import Switchboard

struct AgentTests {
    @Test func worktreeCommandsUseEachAgentsOwnFlag() {
        #expect(Agent.claudeCode.launchCommand(for: .worktree) == "claude -w")
        #expect(Agent.codex.launchCommand(for: .worktree) == "codex --worktree")
    }

    @Test func agentsWithoutWorktreeFlagLaunchPlainly() {
        #expect(Agent.geminiCLI.worktreeFlag == nil)
        #expect(Agent.cursorAgent.worktreeFlag == nil)
        #expect(Agent.geminiCLI.launchCommand(for: .worktree) == "gemini")
        #expect(Agent.cursorAgent.launchCommand(for: .worktree) == "cursor-agent")
    }

    @Test(arguments: [SessionKind.folder, .scratch, .temp])
    func nonWorktreeKindsLaunchPlainly(kind: SessionKind) {
        #expect(Agent.claudeCode.launchCommand(for: kind) == "claude")
        #expect(Agent.codex.launchCommand(for: kind) == "codex")
        #expect(Agent.geminiCLI.launchCommand(for: kind) == "gemini")
        #expect(Agent.cursorAgent.launchCommand(for: kind) == "cursor-agent")
    }

    @Test func repoFolderKindDependsOnWorktreeSupport() {
        let url = URL(fileURLWithPath: "/repo")
        #expect(NewSessionTarget.kind(forFolder: url, agent: .claudeCode, isRepo: { _ in true }) == .worktree)
        #expect(NewSessionTarget.kind(forFolder: url, agent: .geminiCLI, isRepo: { _ in true }) == .folder)
        #expect(NewSessionTarget.kind(forFolder: url, agent: .terminal, isRepo: { _ in true }) == .folder)
        #expect(NewSessionTarget.kind(forFolder: url, agent: .claudeCode, isRepo: { _ in false }) == .folder)
    }

    @Test func launchCommandsLoadSwitchboardHooksBeforeWorktreeFlag() {
        let hooks = HookInstallation(helperPath: "/a b/hook", socketPath: "/s", claudeSettingsPath: "/a b/c.json",
                                     geminiSettingsPath: "/g.json", injectCodexNotify: true, injectGeminiDefaults: true)
        #expect(Agent.claudeCode.launchCommand(for: .worktree, hooks: hooks)
                == #"claude --settings "$SWITCHBOARD_CLAUDE_SETTINGS" -w"#)
        #expect(Agent.codex.launchCommand(for: .folder, hooks: hooks)
                == #"codex -c "$SWITCHBOARD_CODEX_HOOKS" -c "$SWITCHBOARD_CODEX_NOTIFY""#)
        #expect(Agent.geminiCLI.launchCommand(for: .folder, hooks: hooks) == "gemini")
        #expect(hooks.environment(for: .geminiCLI)["GEMINI_CLI_SYSTEM_DEFAULTS_PATH"] == "/g.json")
        #expect(hooks.environment(for: .claudeCode)["SWITCHBOARD_CLAUDE_SETTINGS"] == "/a b/c.json")

        var noNotify = hooks
        noNotify.injectCodexNotify = false
        #expect(Agent.codex.launchCommand(for: .worktree, hooks: noNotify)
                == #"codex -c "$SWITCHBOARD_CODEX_HOOKS" --worktree"#)
        #expect(noNotify.environment(for: .codex)["SWITCHBOARD_CODEX_NOTIFY"] == nil)
    }

    @Test func titleFallsBackFromAgentTitleToTicketToFolderName() {
        var session = Session(kind: .folder, folderPath: "/tmp/api", agent: .codex)
        #expect(session.title == "api")
        session.ticketID = "XYZ-123"
        #expect(session.title == "XYZ-123")
        session.agentTitle = "Fix login"
        #expect(session.title == "Fix login")
    }
}
