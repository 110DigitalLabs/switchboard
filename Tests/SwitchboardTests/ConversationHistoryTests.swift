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

    @Test func readsClaudeFolderPromptAndLatestTitle() throws {
        try write([
            #"{"type":"user","isMeta":true,"message":{"content":"<local-command-caveat>x</local-command-caveat>"},"cwd":"/Users/me/app","entrypoint":"cli"}"#,
            #"{"type":"user","message":{"content":[{"type":"text","text":"fix the login bug\nmore"}]},"cwd":"/Users/me/app"}"#,
            #"{"type":"ai-title","aiTitle":"Login fix"}"#,
            #"{"type":"custom-title","customTitle":"Auth work"}"#,
            #"{"type":"ai-title","aiTitle":"Later title"}"#,
        ], to: claudeFile("c1"), modified: Date(timeIntervalSince1970: 100))

        let found = ConversationHistory.recent(in: locations, directoryExists: { _ in true })
        #expect(found == [PastConversation(agent: .claudeCode, conversationID: "c1", directory: "/Users/me/app",
                                           title: "Auth work", firstPrompt: "fix the login bug",
                                           lastActive: Date(timeIntervalSince1970: 100))])
    }

    @Test func skipsHeadlessClaudeRunsSubagentsAndMissingFolders() throws {
        try write([#"{"type":"user","message":{"content":"hi"},"cwd":"/Users/me/app","entrypoint":"sdk-py"}"#],
                  to: claudeFile("sdk"), modified: Date())
        try write([#"{"type":"user","message":{"content":"hi"},"cwd":"/Users/me/app","entrypoint":"cli"}"#],
                  to: locations.claudeProjects.appendingPathComponent("-Users-me-app/c2/subagents/agent-1.jsonl"),
                  modified: Date())
        try write([#"{"type":"user","message":{"content":"hi"},"cwd":"/gone","entrypoint":"cli"}"#],
                  to: claudeFile("gone"), modified: Date())

        #expect(ConversationHistory.recent(in: locations, directoryExists: { $0 != "/gone" }).isEmpty)
    }

    @Test func readsInteractiveCodexSessionsWithThreadNames() throws {
        let day = locations.codexSessions.appendingPathComponent("2026/11/18")
        try write([#"{"type":"session_meta","payload":{"id":"x1","cwd":"/Users/me/api","source":"cli"}}"#, "{}"],
                  to: day.appendingPathComponent("rollout-a-x1.jsonl"), modified: Date(timeIntervalSince1970: 300))
        try write([#"{"type":"session_meta","payload":{"id":"x2","cwd":"/Users/me/api","source":"exec"}}"#],
                  to: day.appendingPathComponent("rollout-b-x2.jsonl"), modified: Date(timeIntervalSince1970: 400))
        try write([#"{"id":"x1","thread_name":"Old"}"#, #"{"id":"x1","thread_name":"Rate limiter"}"#],
                  to: locations.codexIndex, modified: Date())

        let found = ConversationHistory.recent(in: locations, directoryExists: { _ in true })
        #expect(found.map(\.conversationID) == ["x1"])
        #expect(found.first?.agent == .codex)
        #expect(found.first?.title == "Rate limiter")
    }

    @Test func newestFirstAndLimited() throws {
        for index in 0..<5 {
            try write([#"{"type":"user","message":{"content":"p\#(index)"},"cwd":"/Users/me/app","entrypoint":"cli"}"#],
                      to: claudeFile("c\(index)"), modified: Date(timeIntervalSince1970: Double(index)))
        }
        let found = ConversationHistory.recent(limit: 3, in: locations, directoryExists: { _ in true })
        #expect(found.map(\.conversationID) == ["c4", "c3", "c2"])
    }

    @Test func readsTheTitleFromTheEndOfALongTranscript() throws {
        let filler = String(repeating: "x", count: 1000)
        let lines = [#"{"type":"user","message":{"content":"start"},"cwd":"/Users/me/app","entrypoint":"cli"}"#]
            + Array(repeating: #"{"type":"assistant","text":"\#(filler)"}"#, count: 400)
            + [#"{"type":"ai-title","aiTitle":"Found at the end"}"#]
        try write(lines, to: claudeFile("long"), modified: Date())
        #expect(ConversationHistory.recent(in: locations, directoryExists: { _ in true }).first?.title
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
        #expect(SessionLaunch.reopen(row, hooks: nil, directoryExists: { _ in true }).command == "codex resume x1")
    }

    @Test func recentActivityWindow() {
        let now = Date()
        let conversation = PastConversation(agent: .claudeCode, conversationID: "c", directory: "/",
                                            title: nil, firstPrompt: nil, lastActive: now.addingTimeInterval(-60))
        #expect(conversation.isRecentlyActive(now: now))
        #expect(!conversation.isRecentlyActive(now: now.addingTimeInterval(120)))
    }
}
