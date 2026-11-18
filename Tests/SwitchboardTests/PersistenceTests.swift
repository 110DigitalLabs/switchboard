import Foundation
import Testing
@testable import Switchboard

struct PersistenceTests {
    @Test func roundTripKeepsRowsButNotLiveState() throws {
        var session = Session(kind: .worktree, folderPath: "/repo", agent: .codex,
                              createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        session.agentConversationID = "conv"
        session.workingDirectory = "/repo/wt"
        session.ticketID = "XYZ-1"
        session.linearProjectName = "Core"
        session.prURLs = ["https://x/pr/1"]
        session.agentTitle = "Title"
        session.statusText = "live"
        session.hasBadge = true
        session.workingState = .working
        let state = PersistedState(sessions: [session], collapsedGroups: ["scratch"], selectedID: session.id)

        let decoded = try PersistedState.decode(state.encoded())

        var expected = session
        expected.statusText = nil
        expected.hasBadge = false
        expected.activity = RowActivity()
        #expect(decoded == PersistedState(sessions: [expected], collapsedGroups: ["scratch"], selectedID: session.id))
    }

    @Test func toleratesUnknownMissingAndBadFields() throws {
        let good = UUID(), other = UUID()
        let json = """
        {
          "version": 99, "futureKey": {"a": 1},
          "collapsedGroups": ["ticket:X-1", 5],
          "selectedID": "\(UUID().uuidString)",
          "sessions": [
            {"id": "\(good.uuidString)", "kind": "folder", "folderPath": "/a", "agent": "claudeCode",
             "prURLs": "not-an-array", "createdAt": "garbage", "newField": true},
            {"id": "\(other.uuidString)", "kind": "spaceship", "folderPath": "/b", "agent": "claudeCode"},
            {"kind": "folder"},
            "nonsense"
          ]
        }
        """
        let state = try PersistedState.decode(Data(json.utf8))
        #expect(state.sessions.map(\.id) == [good])
        #expect(state.sessions[0].prURLs == [])
        #expect(state.sessions[0].createdAt == .distantPast)
        #expect(state.collapsedGroups == ["ticket:X-1"])
        #expect(state.selectedID == nil)
    }

    @Test func emptyObjectIsEmptyState() throws {
        #expect(try PersistedState.decode(Data("{}".utf8)) == PersistedState())
    }

    @Test func corruptFileIsBackedUpAndLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swb-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = SessionFile(url: dir.appendingPathComponent("sessions.json"))
        try file.write(Data("[1, 2".utf8))

        let now = Date()
        #expect(file.load(now: now) == PersistedState())
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(try String(contentsOf: file.backupURL(at: now), encoding: .utf8) == "[1, 2")
    }

    @Test func missingFileLoadsEmpty() {
        let file = SessionFile(url: URL(fileURLWithPath: "/nonexistent-\(UUID())/sessions.json"))
        #expect(file.load() == PersistedState())
    }
}
