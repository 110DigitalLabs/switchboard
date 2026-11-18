import AppKit
import Foundation
import Testing
@testable import Switchboard

@MainActor
struct SessionStoreNavigationTests {
    private func makeStore(file: SessionFile? = nil) -> SessionStore {
        let defaults = UserDefaults(suiteName: "SessionStoreNavigationTests-\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        settings.sessionSort = .folder
        return SessionStore(settings: settings, file: file)
    }

    private func add(_ store: SessionStore, _ folder: String, kind: SessionKind = .folder) -> Session {
        let session = Session(kind: kind, folderPath: "/w/\(folder)", agent: .claudeCode)
        store.add(session, startTerminal: false)
        return session
    }

    @Test func positionsFollowVisibleOrder() {
        let store = makeStore()
        let s = add(store, "scratch", kind: .scratch)
        let b = add(store, "b")
        let a = add(store, "a")
        #expect(store.layout.visibleOrder == [a.id, b.id, s.id])
        #expect(store.selectVisible(position: 3) == s.id)
        #expect(store.selectVisible(position: 1) == a.id)
        #expect(store.selectVisible(position: 4) == nil)
        #expect(store.selectedID == a.id)

        store.setCollapsed("sessions", true)
        #expect(store.selectVisible(position: 1) == s.id)
    }

    @Test func adjacentClampsAndStartsFromEnds() {
        let store = makeStore()
        let a = add(store, "a")
        let b = add(store, "b")
        store.selectedID = nil
        #expect(store.selectAdjacent(1) == a.id)
        #expect(store.selectAdjacent(1) == b.id)
        #expect(store.selectAdjacent(1) == b.id)
        #expect(store.selectAdjacent(-1) == a.id)
        #expect(store.selectAdjacent(-1) == a.id)
        store.selectedID = nil
        #expect(store.selectAdjacent(-1) == b.id)
    }

    @Test func navigationKeysDecodeOnlyPlainCommand() {
        #expect(NavigationKey(keyCode: 18, characters: "1", modifiers: .command) == .position(1))
        #expect(NavigationKey(keyCode: 25, characters: "9", modifiers: [.command, .capsLock]) == .position(9))
        #expect(NavigationKey(keyCode: 29, characters: "0", modifiers: .command) == nil)
        #expect(NavigationKey(keyCode: 126, characters: "\u{F700}", modifiers: [.command, .numericPad, .function]) == .previous)
        #expect(NavigationKey(keyCode: 125, characters: "\u{F701}", modifiers: [.command, .function]) == .next)
        #expect(NavigationKey(keyCode: 18, characters: "1", modifiers: [.command, .shift]) == nil)
        #expect(NavigationKey(keyCode: 126, characters: "\u{F700}", modifiers: [.function]) == nil)
        #expect(NavigationKey(keyCode: 8, characters: "c", modifiers: .command) == nil)
    }

    @Test func savesAndRestoresRowsWithoutClosedOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swb-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = SessionFile(url: dir.appendingPathComponent("sessions.json"))

        let store = makeStore(file: file)
        let kept = add(store, "kept")
        let closed = add(store, "closed")
        store.close(closed.id)
        store.selectedID = kept.id
        store.setCollapsed("scratch", true)
        store.saveNow()

        let state = file.load()
        #expect(state.sessions.map(\.id) == [kept.id])
        #expect(state.selectedID == kept.id)
        #expect(state.collapsedGroups == ["scratch"])
    }

    @Test func hookCwdBecomesWorkingDirectory() {
        let store = makeStore()
        let session = add(store, "repo", kind: .worktree)
        store.handle(AgentEvent(rowID: session.id, kind: .sessionStarted, conversationID: "c1",
                                cwd: "/w/repo/.claude/worktrees/x"))
        #expect(store.sessions[0].workingDirectory == "/w/repo/.claude/worktrees/x")
        store.handle(AgentEvent(rowID: session.id, kind: .toolActivity, conversationID: "c1", cwd: "/tmp"))
        #expect(store.sessions[0].workingDirectory == "/w/repo/.claude/worktrees/x")
        store.handle(AgentEvent(rowID: session.id, kind: .sessionStarted, conversationID: "c2"))
        #expect(store.sessions[0].workingDirectory == nil)
    }
}
