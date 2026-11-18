import Foundation
import Testing
@testable import Switchboard

struct SessionLaunchTests {
    private let hooks = HookInstallation(helperPath: "/h", socketPath: "/s", claudeSettingsPath: "/c.json",
                                         geminiSettingsPath: "/g.json", injectCodexNotify: true,
                                         injectGeminiDefaults: true)

    @Test func resumeCommandsUseEachAgentsSyntax() {
        #expect(Agent.claudeCode.resumeCommand(conversationID: "abc-1") == "claude --resume abc-1")
        #expect(Agent.codex.resumeCommand(conversationID: "abc-1") == "codex resume abc-1")
        #expect(Agent.geminiCLI.resumeCommand(conversationID: "abc-1") == "gemini --resume abc-1")
        #expect(Agent.cursorAgent.resumeCommand(conversationID: "abc-1") == "cursor-agent --resume abc-1")
    }

    @Test func resumeCommandsKeepSwitchboardHooks() {
        #expect(Agent.claudeCode.resumeCommand(conversationID: "id", hooks: hooks)
                == #"claude --settings "$SWITCHBOARD_CLAUDE_SETTINGS" --resume id"#)
        #expect(Agent.codex.resumeCommand(conversationID: "id", hooks: hooks)
                == #"codex resume -c "$SWITCHBOARD_CODEX_HOOKS" -c "$SWITCHBOARD_CODEX_NOTIFY" id"#)
    }

    @Test func unsafeConversationIDsAreQuoted() {
        #expect(Agent.claudeCode.resumeCommand(conversationID: "a b;rm") == "claude --resume 'a b;rm'")
    }

    private func worktreeSession(conversation: String?, workingDirectory: String?) -> Session {
        var session = Session(kind: .worktree, folderPath: "/repo", agent: .claudeCode)
        session.agentConversationID = conversation
        session.workingDirectory = workingDirectory
        return session
    }

    @Test func resumesInsideTheAgentsWorktree() {
        let session = worktreeSession(conversation: "c1", workingDirectory: "/repo/.claude/worktrees/x")
        let launch = SessionLaunch.reopen(session, hooks: nil, directoryExists: { _ in true })
        #expect(launch == SessionLaunch(directory: "/repo/.claude/worktrees/x", command: "claude --resume c1"))
    }

    @Test func resumesInFolderWhenNoWorkingDirectoryWasReported() {
        let session = worktreeSession(conversation: "c1", workingDirectory: nil)
        let launch = SessionLaunch.reopen(session, hooks: nil, directoryExists: { _ in true })
        #expect(launch == SessionLaunch(directory: "/repo", command: "claude --resume c1"))
    }

    @Test func missingWorktreeFallsBackToFreshAgentInRepo() {
        let session = worktreeSession(conversation: "c1", workingDirectory: "/repo/.claude/worktrees/gone")
        let launch = SessionLaunch.reopen(session, hooks: nil, directoryExists: { $0 == "/repo" })
        #expect(launch == SessionLaunch(directory: "/repo", command: "claude -w"))
    }

    @Test func noConversationStartsFreshInFolder() {
        let session = worktreeSession(conversation: nil, workingDirectory: "/repo/.claude/worktrees/x")
        let launch = SessionLaunch.reopen(session, hooks: nil, directoryExists: { _ in true })
        #expect(launch == SessionLaunch(directory: "/repo", command: "claude -w"))
    }

    @Test func missingFolderOpensBareShellAtHome() {
        let session = worktreeSession(conversation: "c1", workingDirectory: nil)
        let launch = SessionLaunch.reopen(session, hooks: nil, home: "/Users/me", directoryExists: { _ in false })
        #expect(launch == SessionLaunch(directory: "/Users/me", command: nil))
    }
}
