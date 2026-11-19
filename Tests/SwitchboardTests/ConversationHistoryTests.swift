import Foundation
import Testing
@testable import Switchboard

struct ConversationHistoryTests {
    private let root: URL
    private let locations: ConversationHistory.Locations

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        locations = ConversationHistory.Locations(
            claudeProjects: root.appendingPathComponent("claude/projects"),
            claudeSessions: root.appendingPathComponent("claude/sessions"),
            codexSessions: root.appendingPathComponent("codex/sessions"),
            codexIndex: root.appendingPathComponent("codex/session_index.jsonl"))
        try FileManager.default.createDirectory(at: locations.claudeProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.codexSessions, withIntermediateDirectories: true)
    }

    private func write(_ lines: [String], to url: URL, modified: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func claudeFile(_ id: String) -> URL {
        locations.claudeProjects.appendingPathComponent("-Users-me-app/\(id).jsonl")
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func process(_ pid: Int32, _ arguments: String, started: Date? = nil,
                         parent: Int32 = 1) -> ActiveConversations.RunningProcess {
        .init(pid: pid, parent: parent, started: started ?? now.addingTimeInterval(-600),
              arguments: arguments.split(separator: " ").map(String.init))
    }

    private func register(pid: Int32, id: String, startedAt: Date? = nil, kind: String = "interactive") throws {
        let millis = Int((startedAt ?? now.addingTimeInterval(-598)).timeIntervalSince1970 * 1000)
        try write([#"{"pid":\#(pid),"sessionId":"\#(id)","startedAt":\#(millis),"kind":"\#(kind)","cwd":"/Users/me/app"}"#],
                  to: locations.claudeSessions.appendingPathComponent("\(pid).json"), modified: now)
    }

    private func claudeTranscript(_ id: String, prompt: String = "hi", modified: Date? = nil) throws {
        try write([#"{"type":"user","message":{"content":"\#(prompt)"},"cwd":"/Users/me/app","entrypoint":"cli"}"#],
                  to: claudeFile(id), modified: modified ?? now)
    }

    private func active(_ processes: [ActiveConversations.RunningProcess],
                        directories: [Int32: String] = [:]) -> [PastConversation] {
        ActiveConversations.list(in: locations, processes: processes, excludingDescendantsOf: 500,
                                 workingDirectories: { _ in directories },
                                 directoryExists: { $0 != "/gone" })
    }

    @Test func readsClaudeFolderPromptAndLatestTitle() throws {
        try write([
            #"{"type":"user","isMeta":true,"message":{"content":"<local-command-caveat>x</local-command-caveat>"},"cwd":"/Users/me/app","entrypoint":"cli"}"#,
            #"{"type":"user","message":{"content":[{"type":"text","text":"fix the login bug\nmore"}]},"cwd":"/Users/me/app"}"#,
            #"{"type":"ai-title","aiTitle":"Login fix"}"#,
            #"{"type":"custom-title","customTitle":"Auth work"}"#,
            #"{"type":"ai-title","aiTitle":"Later title"}"#,
        ], to: claudeFile("c1"), modified: Date(timeIntervalSince1970: 100))

        let found = ConversationHistory.claudeConversation(at: claudeFile("c1"), modified: Date(timeIntervalSince1970: 100))
        #expect(found == PastConversation(agent: .claudeCode, conversationID: "c1", directory: "/Users/me/app",
                                          title: "Auth work", firstPrompt: "fix the login bug",
                                          lastActive: Date(timeIntervalSince1970: 100)))
    }

    @Test func listsOnlyClaudeSessionsWhoseProcessIsRunning() throws {
        try claudeTranscript("live")
        try claudeTranscript("closed")
        try claudeTranscript("reused")
        try claudeTranscript("headless")
        try register(pid: 10, id: "live")
        try register(pid: 11, id: "closed")
        try register(pid: 12, id: "reused", startedAt: now.addingTimeInterval(-90_000))
        try register(pid: 13, id: "headless", kind: "print")

        let found = active([process(10, "claude"), process(12, "claude"), process(13, "claude -p x")])
        #expect(found.map(\.conversationID) == ["live"])
    }

    @Test func leavesOutAgentsStartedInsideSwitchboardsOwnTerminals() throws {
        try claudeTranscript("outside")
        try claudeTranscript("in-row")
        try register(pid: 30, id: "outside")
        try register(pid: 31, id: "in-row")

        // 500 is the app, 501 a row's shell, 31 the claude typed into it.
        let found = active([process(501, "-zsh", parent: 500), process(31, "claude", parent: 501),
                            process(30, "claude", parent: 2)])
        #expect(found.map(\.conversationID) == ["outside"])
    }

    @Test func skipsHeadlessClaudeTranscriptsAndMissingFolders() throws {
        try write([#"{"type":"user","message":{"content":"hi"},"cwd":"/Users/me/app","entrypoint":"sdk-py"}"#],
                  to: claudeFile("sdk"), modified: now)
        try write([#"{"type":"user","message":{"content":"hi"},"cwd":"/gone","entrypoint":"cli"}"#],
                  to: claudeFile("gone"), modified: now)
        try register(pid: 20, id: "sdk")
        try register(pid: 21, id: "gone")

        #expect(active([process(20, "claude"), process(21, "claude")]).isEmpty)
    }

    @Test func matchesRunningCodexToItsRollout() throws {
        let day = locations.codexSessions.appendingPathComponent("2026/11/18")
        func rollout(_ id: String, cwd: String, created: Date, modified: Date? = nil) throws {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
            try write([#"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","source":"cli"}}"#, "{}"],
                      to: day.appendingPathComponent("rollout-\(formatter.string(from: created))-\(id).jsonl"),
                      modified: modified ?? created.addingTimeInterval(30))
        }
        try rollout("before", cwd: "/Users/me/api", created: now.addingTimeInterval(-900))
        try rollout("mine", cwd: "/Users/me/api", created: now.addingTimeInterval(-300))
        try rollout("elsewhere", cwd: "/Users/me/web", created: now.addingTimeInterval(-200))
        // Resuming appends to the original rollout.
        try rollout("resumed", cwd: "/Users/me/old", created: now.addingTimeInterval(-90_000),
                    modified: now.addingTimeInterval(-60))
        try write([#"{"id":"mine","thread_name":"Rate limiter"}"#], to: locations.codexIndex, modified: now)

        let found = active([
            process(30, "/opt/homebrew/bin/codex"),
            process(31, "codex resume resumed"),
            process(32, "codex exec do-it"),
            process(33, "codex", parent: 30),
        ], directories: [30: "/Users/me/api", 33: "/Users/me/web"])
        #expect(Set(found.map(\.conversationID)) == ["mine", "resumed"])
        #expect(found.first { $0.conversationID == "mine" }?.title == "Rate limiter")
    }

    @Test func knowsWhichClaudeConversationsStillHaveATranscript() throws {
        #expect(ConversationHistory.exists(agent: .claudeCode, conversationID: "c1", in: locations))
        try claudeTranscript("c1")
        #expect(ConversationHistory.exists(agent: .claudeCode, conversationID: "c1", in: locations))
        #expect(!ConversationHistory.exists(agent: .claudeCode, conversationID: "deleted", in: locations))
        #expect(ConversationHistory.exists(agent: .codex, conversationID: "deleted", in: locations))
    }

    @Test func parsesPsAndLsofOutput() {
        let ps = """
          83684 83667 Wed Nov 18 17:19:29 2026     claude --resume c2d7
            501     1 Sun Nov  8 09:01:02 2026     /opt/homebrew/bin/codex resume x1
        garbage
        """
        let processes = ActiveConversations.parseProcesses(ps)
        #expect(processes.map(\.pid) == [83684, 501])
        #expect(processes.last?.arguments == ["/opt/homebrew/bin/codex", "resume", "x1"])
        #expect(processes.first?.parent == 83667)
        #expect(ActiveConversations.parseWorkingDirectories("p42\nfcwd\nn/Users/me/my app\np43\nn/tmp\n")
                == [42: "/Users/me/my app", 43: "/tmp"])
    }

    @Test func readsTheTitleFromTheEndOfALongTranscript() throws {
        let filler = String(repeating: "x", count: 1000)
        let lines = [#"{"type":"user","message":{"content":"start"},"cwd":"/Users/me/app","entrypoint":"cli"}"#]
            + Array(repeating: #"{"type":"assistant","text":"\#(filler)"}"#, count: 400)
            + [#"{"type":"ai-title","aiTitle":"Found at the end"}"#]
        try write(lines, to: claudeFile("long"), modified: Date())
        #expect(ConversationHistory.claudeConversation(at: claudeFile("long"), modified: Date())?.title
                == "Found at the end")
    }

    @Test @MainActor func resumingMakesAFolderRowForTheConversation() {
        let conversation = PastConversation(agent: .codex, conversationID: "x1", directory: "/Users/me/api",
                                            title: nil, firstPrompt: "add tests", lastActive: Date())
        let row = SessionStore.row(resuming: conversation)
        #expect(row.kind == .folder)
        #expect(row.agent == .codex)
        #expect(row.agentConversationID == "x1")
        #expect(row.agentTitle == "add tests")
        #expect(SessionLaunch.reopen(row, hooks: nil, directoryExists: { _ in true },
                                     conversationExists: { _, _ in true }).command == "codex resume x1")
    }

    @Test @MainActor func elsewhereLeavesOutConversationsRowsHereOwn() {
        let store = SessionStore(settings: AppSettings(defaults: UserDefaults(suiteName: "elsewhere-\(UUID())")!))
        let mine = PastConversation(agent: .claudeCode, conversationID: "mine", directory: "/a",
                                    title: nil, firstPrompt: nil, lastActive: now)
        let theirs = PastConversation(agent: .codex, conversationID: "theirs", directory: "/b",
                                      title: nil, firstPrompt: nil, lastActive: now)
        store.add(SessionStore.row(resuming: mine), startTerminal: false)
        store.updateElsewhere([mine, theirs])
        #expect(store.elsewhere == [theirs])
    }

    @Test func recentActivityWindow() {
        let now = Date()
        let conversation = PastConversation(agent: .claudeCode, conversationID: "c", directory: "/",
                                            title: nil, firstPrompt: nil, lastActive: now.addingTimeInterval(-60))
        #expect(conversation.isRecentlyActive(now: now))
        #expect(!conversation.isRecentlyActive(now: now.addingTimeInterval(120)))
    }
}
