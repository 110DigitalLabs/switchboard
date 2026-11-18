import Foundation
import Testing
@testable import Switchboard

@MainActor
struct HandoverTests {
    private let repo = Repo(url: URL(fileURLWithPath: "/home/api"), relativePath: "api")

    @Test func summaryCommandsForkWithoutTouchingTheOriginal() throws {
        let claude = try #require(HandoverCommand.summaryArguments(agent: .claudeCode, conversationID: "abc"))
        #expect(Array(claude.dropLast()) == ["claude", "-p", "--resume", "abc", "--fork-session",
                                             "--no-session-persistence"])
        let codex = try #require(HandoverCommand.summaryArguments(agent: .codex, conversationID: "abc"))
        #expect(Array(codex.dropLast()) == ["codex", "exec", "fork", "--ephemeral", "--skip-git-repo-check", "abc"])
        #expect(claude.last == HandoverCommand.summaryPrompt && codex.last == HandoverCommand.summaryPrompt)
        #expect(HandoverCommand.summaryArguments(agent: .geminiCLI, conversationID: "abc") == nil)
        #expect(HandoverCommand.summaryArguments(agent: .cursorAgent, conversationID: "abc") == nil)
    }

    @Test func shellLineQuotesThePrompt() {
        #expect(HandoverCommand.shellLine(["claude", "-p", "it's here"]) == #"exec claude -p 'it'\''s here'"#)
    }

    @Test func initialPromptInlinesShortSummariesAndReferencesFiles() {
        let url = URL(string: "https://linear.app/acme/issue/ENG-5")
        let inline = HandoverCommand.initialPrompt(ticketID: "ENG-5", ticketTitle: "Fix", ticketURL: url,
                                                   summary: "Half done.", summaryFile: nil)
        #expect(inline.contains("ENG-5 (Fix), https://linear.app/acme/issue/ENG-5"))
        #expect(inline.contains("Handover summary from the previous session: Half done."))
        let file = HandoverCommand.initialPrompt(ticketID: nil, ticketTitle: nil, ticketURL: nil,
                                                 summary: "x\ny", summaryFile: "/s/h.md")
        #expect(file.contains("/s/h.md") && !file.contains("x\ny"))
        #expect(!file.contains("\n"))
        #expect(HandoverCommand.needsFile("a\nb"))
        #expect(HandoverCommand.needsFile(String(repeating: "a", count: 401)))
        #expect(!HandoverCommand.needsFile("short"))
    }

    @Test func worktreeLaunchPutsPromptBeforeWorktreeFlag() {
        let options = AgentLaunchOptions(prompt: "go on")
        #expect(Agent.claudeCode.launchCommand(for: .worktree, options: options) == "claude 'go on' -w")
        #expect(Agent.codex.launchCommand(for: .worktree, options: options) == "codex 'go on' --worktree")
        #expect(Agent.geminiCLI.launchCommand(for: .folder, options: options) == "gemini -i 'go on'")
        #expect(Agent.cursorAgent.launchCommand(for: .folder, options: options) == "cursor-agent 'go on'")
        #expect(Agent.codex.launchCommand(for: .temp, options: AgentLaunchOptions(planMode: true)) == "codex")
    }

    @Test func eligibility() {
        var folder = TicketTestSupport.session(.folder)
        #expect(!folder.canMoveToWorktree)
        folder.agentConversationID = "c"
        #expect(folder.canMoveToWorktree)
        #expect(TicketTestSupport.session(.temp, ticket: "ENG-1").canMoveToWorktree)
        #expect(!TicketTestSupport.session(.worktree, ticket: "ENG-1").canMoveToWorktree)
        #expect(!TicketTestSupport.session(.scratch, ticket: "ENG-1").canMoveToWorktree)
    }

    @Test func handedOverKeepsIdentityAndTicket() {
        var old = TicketTestSupport.session(.temp, path: "/home/tickets/ENG-1", ticket: "ENG-1", created: 5)
        old.ticketTitle = "T"
        old.agentConversationID = "c"
        old.agentTitle = "Plan"
        old.workingDirectory = "/home/tickets/ENG-1"
        old.prURLs = ["https://github.com/a/b/pull/1"]
        let next = old.handedOver(to: repo, isRepo: { _ in true })
        #expect(next.id == old.id && next.createdAt == old.createdAt)
        #expect(next.kind == .worktree && next.folderPath == "/home/api")
        #expect(next.ticketID == "ENG-1" && next.ticketTitle == "T" && next.prURLs == old.prURLs)
        #expect(next.agentConversationID == nil && next.agentTitle == nil && next.workingDirectory == nil)
    }

    @Test func storeSwapsSummaryIntoSameRow() async throws {
        let directory = TicketTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TicketTestSupport.store()
        store.handoverDirectory = directory
        var ran: [(String, String)] = []
        store.runSummary = { line, cwd in
            ran.append((line, cwd))
            return "Goal: X.\nDone: Y."
        }
        let other = TicketTestSupport.session(.folder, path: "/tmp/other")
        var session = TicketTestSupport.session(.folder, path: "/tmp/api", ticket: "ENG-1")
        session.agentConversationID = "conv-1"
        session.workingDirectory = "/tmp/api"
        store.add(session, startTerminal: false)
        store.add(other, startTerminal: false)

        await store.moveToWorktree(session.id, repo: repo, startTerminal: false, isRepo: { _ in true })

        #expect(ran.count == 1)
        #expect(ran[0].0.hasPrefix("exec claude -p --resume conv-1 --fork-session"))
        #expect(ran[0].1 == "/tmp/api")
        #expect(store.sessions.map(\.id) == [session.id, other.id])
        let swapped = store.sessions[0]
        #expect(swapped.kind == .worktree && swapped.folderPath == "/home/api")
        #expect(swapped.agentConversationID == nil && swapped.ticketID == "ENG-1")
        #expect(store.handoverProgress.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1 && files[0].hasPrefix("ENG-1-"))
        let saved = try String(contentsOf: directory.appendingPathComponent(files[0]), encoding: .utf8)
        #expect(saved == "Goal: X.\nDone: Y.\n")
        #expect(store.persistedState.sessions[0].folderPath == "/home/api")
    }

    @Test func failedSummaryLeavesRowUntouched() async {
        let store = TicketTestSupport.store()
        store.runSummary = { _, _ in throw SummaryProcess.Failure(message: "boom") }
        var session = TicketTestSupport.session(.folder, path: "/tmp/api")
        session.agentConversationID = "conv-1"
        store.add(session, startTerminal: false)
        await store.moveToWorktree(session.id, repo: repo, startTerminal: false, isRepo: { _ in true })
        #expect(store.sessions == [session])
        #expect(store.errorMessage?.contains("boom") == true)
    }

    @Test func agentWithoutForkSkipsSummary() async {
        let store = TicketTestSupport.store()
        var called = false
        store.runSummary = { _, _ in called = true; return "" }
        var session = TicketTestSupport.session(.temp, path: "/tmp/t", ticket: "ENG-2", agent: .geminiCLI)
        session.agentConversationID = "conv"
        store.add(session, startTerminal: false)
        await store.moveToWorktree(session.id, repo: repo, startTerminal: false, isRepo: { _ in true })
        #expect(!called)
        #expect(store.sessions[0].folderPath == "/home/api" && store.sessions[0].kind == .folder)
    }
}
