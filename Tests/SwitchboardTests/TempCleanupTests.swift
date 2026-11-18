import Foundation
import Testing
@testable import Switchboard

struct TempCleanupPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let day: TimeInterval = 86_400

    private func kept(_ kind: SessionKind = .temp, closedDaysAgo: Double?) -> Session {
        var session = Session(kind: kind, folderPath: "/h/tickets/X", agent: .claudeCode)
        session.closedAt = closedDaysAgo.map { now.addingTimeInterval(-$0 * day) }
        return session
    }

    @Test func onlyKeptRowsOlderThanNDaysExpire() {
        let old = kept(closedDaysAgo: 31)
        let exactly = kept(closedDaysAgo: 30)
        let recent = kept(.scratch, closedDaysAgo: 2)
        let live = kept(closedDaysAgo: nil)
        let oldScratch = kept(.scratch, closedDaysAgo: 45)
        let expired = TempCleanupPolicy.expired([old, exactly, recent, live, oldScratch], now: now, days: 30)
        #expect(expired == [old.id, oldScratch.id])
        #expect(TempCleanupPolicy.expired([recent], now: now, days: 1) == [recent.id])
        #expect(TempCleanupPolicy.expired([], now: now, days: 30).isEmpty)
    }

    @Test func daysRemainingRoundsUpAndStopsAtZero() {
        let closed = now.addingTimeInterval(-2.5 * day)
        #expect(TempCleanupPolicy.daysRemaining(closedAt: closed, now: now, days: 30) == 28)
        #expect(TempCleanupPolicy.daysRemaining(closedAt: now, now: now, days: 30) == 30)
        #expect(TempCleanupPolicy.daysRemaining(closedAt: now.addingTimeInterval(-40 * day), now: now, days: 30) == 0)
        #expect(TempCleanupPolicy.keptNote(closedAt: closed, now: now, days: 30) == "kept · deletes in 28 days")
        #expect(TempCleanupPolicy.keptNote(closedAt: now.addingTimeInterval(-29.5 * day), now: now, days: 30)
                == "kept · deletes in 1 day")
    }

    @Test func onlyLiveTempAndScratchRowsAskBeforeClosing() {
        #expect(TempCleanupPolicy.asksBeforeClosing(kept(.temp, closedDaysAgo: nil)))
        #expect(TempCleanupPolicy.asksBeforeClosing(kept(.scratch, closedDaysAgo: nil)))
        #expect(!TempCleanupPolicy.asksBeforeClosing(kept(.temp, closedDaysAgo: 1)))
        #expect(!TempCleanupPolicy.asksBeforeClosing(kept(.worktree, closedDaysAgo: nil)))
        #expect(!TempCleanupPolicy.asksBeforeClosing(kept(.folder, closedDaysAgo: nil)))
    }

    @Test func keptRowsSitAtTheBottomOfTempAndAreSkippedByNavigation() {
        var liveTemp = Session(kind: .temp, folderPath: "/h/tickets/A", agent: .claudeCode)
        liveTemp.ticketID = "ENG-1"
        let liveScratch = Session(kind: .scratch, folderPath: "/h/scratch/1", agent: .claudeCode)
        var keptScratch = Session(kind: .scratch, folderPath: "/h/scratch/2", agent: .claudeCode)
        keptScratch.closedAt = now
        let folder = Session(kind: .folder, folderPath: "/h/api", agent: .claudeCode)
        let layout = SessionOrdering.layout(sessions: [keptScratch, liveTemp, liveScratch, folder],
                                            sort: .folder, grouping: .none)
        #expect(layout.sections.map(\.id) == ["sessions", "scratch", "temp"])
        let tempIDs = layout.sections[2].items.map(\.id)
        #expect(tempIDs == [liveTemp.id.uuidString, keptScratch.id.uuidString])
        #expect(layout.visibleOrder == [folder.id, liveScratch.id, liveTemp.id])
    }

    @Test func keptRowsDoNotCountAsExistingTicketSessions() {
        var kept = Session(kind: .temp, folderPath: "/h/tickets/ENG-1", agent: .claudeCode)
        kept.ticketID = "ENG-1"
        kept.closedAt = now
        #expect(TicketSessions.existing(for: "ENG-1", in: [kept]).isEmpty)
        #expect(TicketSessions.unstarted([TicketTestSupport.issue("ENG-1")], sessions: [kept]).count == 1)
    }

    @Test func closedAtRoundTrips() throws {
        let session = kept(closedDaysAgo: 3)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded.closedAt == session.closedAt)
        let live = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(kept(closedDaysAgo: nil)))
        #expect(live.closedAt == nil)
    }
}

/// Real folders on disk, including symlink and `..` attacks.
struct TempFolderSafetyTests {
    private let fm = FileManager.default

    private func makeHome() throws -> (home: URL, outside: URL) {
        let base = TicketTestSupport.tempDirectory()
        let home = base.appendingPathComponent("home", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        for name in ["tickets/ENG-1", "reviews/a-b-1", "scratch/20260101-000000", "api/src"] {
            try fm.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        return (home, outside)
    }

    private func isDeletable(_ path: String, _ home: URL) -> Bool {
        if case .deletable = TempFolderSafety.check(path, home: home) { return true }
        return false
    }

    @Test func foldersStrictlyInsideTheThreeRootsAreDeletable() throws {
        let (home, _) = try makeHome()
        for name in ["tickets/ENG-1", "reviews/a-b-1", "scratch/20260101-000000"] {
            let path = home.appendingPathComponent(name).path
            guard case .deletable(let url) = TempFolderSafety.check(path, home: home) else {
                Issue.record("\(name) should be deletable"); continue
            }
            #expect(url.path == TempFolderSafety.realPath(path))
        }
    }

    @Test func rootsThemselvesHomeAndOtherFoldersAreRefused() throws {
        let (home, outside) = try makeHome()
        for path in [home.appendingPathComponent("tickets").path, home.appendingPathComponent("reviews").path,
                     home.appendingPathComponent("scratch").path, home.appendingPathComponent("scratch/").path,
                     home.path, home.appendingPathComponent("api").path, outside.path, "/", "relative/tickets/x"] {
            #expect(!isDeletable(path, home), "\(path)")
        }
    }

    @Test func dotDotIsRefusedEvenWhenItWouldLandInside() throws {
        let (home, _) = try makeHome()
        let escape = home.path + "/tickets/../api"
        let staysInside = home.path + "/tickets/ENG-1/../ENG-1"
        #expect(TempFolderSafety.check(escape, home: home) == .refused("path contains . or .."))
        #expect(TempFolderSafety.check(staysInside, home: home) == .refused("path contains . or .."))
        #expect(!isDeletable(home.path + "/tickets/./ENG-1", home))
    }

    @Test func symlinkedFolderPointingOutsideIsRefused() throws {
        let (home, outside) = try makeHome()
        let link = home.appendingPathComponent("tickets/EVIL")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!isDeletable(link.path, home))
        // Even a link to a sibling inside the root is not followed.
        let inner = home.appendingPathComponent("tickets/ALIAS")
        try fm.createSymbolicLink(at: inner, withDestinationURL: home.appendingPathComponent("tickets/ENG-1"))
        #expect(!isDeletable(inner.path, home))
    }

    @Test func pathThroughASymlinkedParentThatLeavesTheRootIsRefused() throws {
        let (home, outside) = try makeHome()
        try fm.createDirectory(at: outside.appendingPathComponent("victim"), withIntermediateDirectories: true)
        let hop = home.appendingPathComponent("tickets/hop")
        try fm.createSymbolicLink(at: hop, withDestinationURL: outside)
        #expect(!isDeletable(hop.appendingPathComponent("victim").path, home))
    }

    @Test func symlinkedRootIsRefused() throws {
        let (home, outside) = try makeHome()
        try fm.removeItem(at: home.appendingPathComponent("scratch"))
        try fm.createDirectory(at: outside.appendingPathComponent("x"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent("scratch"), withDestinationURL: outside)
        #expect(!isDeletable(home.appendingPathComponent("scratch/x").path, home))
    }

    @Test func homeBehindASymlinkStillWorks() throws {
        let (home, _) = try makeHome()
        let alias = home.deletingLastPathComponent().appendingPathComponent("home-alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: home)
        #expect(isDeletable(alias.appendingPathComponent("tickets/ENG-1").path, alias))
        #expect(isDeletable(home.appendingPathComponent("tickets/ENG-1").path, alias))
    }

    @Test func filesAndMissingPathsAreNotDeleted() throws {
        let (home, _) = try makeHome()
        let file = home.appendingPathComponent("tickets/notes.txt")
        try Data("x".utf8).write(to: file)
        #expect(TempFolderSafety.check(file.path, home: home) == .refused("not a directory"))
        #expect(TempFolderSafety.check(home.path + "/tickets/GONE", home: home) == .missing)
    }
}

@MainActor
struct SessionStoreClosingTests {
    private func setup() throws -> (SessionStore, URL, trashed: () -> [String]) {
        let home = TicketTestSupport.tempDirectory()
        for name in ["tickets", "reviews", "scratch"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        let store = TicketTestSupport.store(home: home)
        var trashed: [String] = []
        store.trashItem = { trashed.append($0.path) }
        return (store, home, { trashed })
    }

    private func folder(_ home: URL, _ name: String) throws -> String {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    @Test func closingTempOrScratchAsksButWorktreeAndFolderCloseDirectly() throws {
        let (store, home, trashed) = try setup()
        let temp = Session(kind: .temp, folderPath: try folder(home, "tickets/ENG-1"), agent: .claudeCode)
        let worktree = Session(kind: .worktree, folderPath: try folder(home, "api"), agent: .claudeCode)
        let plain = Session(kind: .folder, folderPath: try folder(home, "notes"), agent: .claudeCode)
        for session in [temp, worktree, plain] { store.add(session, startTerminal: false) }

        store.requestClose(temp.id)
        #expect(store.closeRequestID == temp.id)
        #expect(store.sessions.count == 3)
        store.requestClose(worktree.id)
        store.requestClose(plain.id)
        #expect(store.sessions.map(\.id) == [temp.id])
        #expect(trashed().isEmpty)
    }

    @Test func deleteTrashesASafeFolderAndDropsTheRow() throws {
        let (store, home, trashed) = try setup()
        let path = try folder(home, "reviews/a-b-1")
        let review = Session(kind: .temp, folderPath: path, agent: .claudeCode)
        store.add(review, startTerminal: false)
        store.closeDeletingFolder(review.id)
        #expect(store.sessions.isEmpty)
        #expect(trashed() == [TempFolderSafety.realPath(path)])
        #expect(store.errorMessage == nil)
    }

    @Test func deleteRefusesUnsafeOrSharedFolders() throws {
        let (store, home, trashed) = try setup()
        let outside = Session(kind: .scratch, folderPath: try folder(home, "api"), agent: .claudeCode)
        store.add(outside, startTerminal: false)
        store.closeDeletingFolder(outside.id)
        #expect(store.sessions.isEmpty)
        #expect(store.errorMessage != nil)

        let shared = try folder(home, "tickets/ENG-2")
        let a = Session(kind: .temp, folderPath: shared, agent: .claudeCode)
        let b = Session(kind: .temp, folderPath: shared, agent: .claudeCode)
        store.add(a, startTerminal: false)
        store.add(b, startTerminal: false)
        store.closeDeletingFolder(a.id)
        #expect(store.sessions.map(\.id) == [b.id])
        #expect(trashed().isEmpty)
    }

    @Test func deleteRefusesWhenAnotherRowIsInsideOrContainsTheFolder() throws {
        let (store, home, trashed) = try setup()
        let target = try folder(home, "tickets/ENG-3")
        let nested = try folder(home, "tickets/ENG-3/sub")

        // Another row's folder inside the target.
        let a = Session(kind: .temp, folderPath: target, agent: .claudeCode)
        let inside = Session(kind: .folder, folderPath: nested, agent: .claudeCode)
        store.add(a, startTerminal: false)
        store.add(inside, startTerminal: false)
        store.closeDeletingFolder(a.id)
        #expect(trashed().isEmpty)
        store.close(inside.id)

        // Another row's working directory inside the target.
        let b = Session(kind: .temp, folderPath: target, agent: .claudeCode)
        var worker = Session(kind: .worktree, folderPath: try folder(home, "api"), agent: .claudeCode)
        worker.workingDirectory = nested
        store.add(b, startTerminal: false)
        store.add(worker, startTerminal: false)
        store.closeDeletingFolder(b.id)
        #expect(trashed().isEmpty)
        store.close(worker.id)

        // Another row's folder containing the target.
        let c = Session(kind: .scratch, folderPath: nested, agent: .claudeCode)
        let outer = Session(kind: .folder, folderPath: target, agent: .claudeCode)
        store.add(c, startTerminal: false)
        store.add(outer, startTerminal: false)
        store.closeDeletingFolder(c.id)
        #expect(trashed().isEmpty)
        store.close(outer.id)

        // A sibling whose name only shares a prefix does not block deletion.
        let d = Session(kind: .temp, folderPath: target, agent: .claudeCode)
        let sibling = Session(kind: .temp, folderPath: try folder(home, "tickets/ENG-30"), agent: .claudeCode)
        store.add(d, startTerminal: false)
        store.add(sibling, startTerminal: false)
        store.closeDeletingFolder(d.id)
        #expect(trashed() == [TempFolderSafety.realPath(target)])
    }

    @Test func overlapCoversEqualInsideContainingAndUnresolvedPaths() {
        #expect(SessionStore.overlaps("/x/tickets/A", "/x/tickets/A"))
        #expect(SessionStore.overlaps("/x/tickets/A/b/c", "/x/tickets/A"))
        #expect(SessionStore.overlaps("/x/tickets", "/x/tickets/A"))
        #expect(SessionStore.overlaps("/x/tickets/A/../A/b", "/x/tickets/A"))
        #expect(!SessionStore.overlaps("/x/tickets/AB", "/x/tickets/A"))
        #expect(!SessionStore.overlaps("/y/other", "/x/tickets/A"))
    }

    @Test func keepLeavesAClosedRowThatCanBeReopenedOrDeleted() throws {
        let (store, home, trashed) = try setup()
        let path = try folder(home, "scratch/1")
        var session = Session(kind: .scratch, folderPath: path, agent: .claudeCode)
        session.hasBadge = true
        store.add(session, startTerminal: false)
        let now = Date(timeIntervalSince1970: 5_000)
        store.closeKeepingFolder(session.id, now: now)
        #expect(store.sessions[0].closedAt == now)
        #expect(!store.sessions[0].hasBadge)
        #expect(store.layout.sections.map(\.id) == ["temp"])
        #expect(store.layout.visibleOrder.isEmpty)

        store.requestClose(session.id)
        #expect(store.closeRequestID == nil)

        store.deleteKept(session.id)
        #expect(store.sessions.isEmpty)
        #expect(trashed() == [TempFolderSafety.realPath(path)])
    }

    @Test func cleanupTrashesOnlyExpiredKeptRows() throws {
        let (store, home, trashed) = try setup()
        store.settings.tempCleanupDays = 7
        let now = Date(timeIntervalSince1970: 10_000_000)
        var old = Session(kind: .temp, folderPath: try folder(home, "tickets/OLD-1"), agent: .claudeCode)
        old.closedAt = now.addingTimeInterval(-8 * 86_400)
        var recent = Session(kind: .temp, folderPath: try folder(home, "tickets/NEW-1"), agent: .claudeCode)
        recent.closedAt = now.addingTimeInterval(-6 * 86_400)
        let live = Session(kind: .temp, folderPath: try folder(home, "tickets/LIVE-1"), agent: .claudeCode)
        var escaped = Session(kind: .temp, folderPath: home.path + "/tickets/../api", agent: .claudeCode)
        escaped.closedAt = now.addingTimeInterval(-30 * 86_400)
        for session in [old, recent, live, escaped] { store.add(session, startTerminal: false) }

        #expect(store.runTempCleanup(now: now) == [old.id, escaped.id])
        #expect(store.sessions.map(\.id) == [recent.id, live.id])
        #expect(trashed() == [TempFolderSafety.realPath(old.folderPath)])
    }

    @Test func restoreLeavesKeptRowsClosed() throws {
        let dir = TicketTestSupport.tempDirectory()
        let file = SessionFile(url: dir.appendingPathComponent("sessions.json"))
        var kept = Session(kind: .temp, folderPath: dir.path, agent: .claudeCode)
        kept.closedAt = Date(timeIntervalSince1970: 1_000)
        let writer = SessionStore(settings: AppSettings(defaults: UserDefaults(suiteName: "w-\(UUID())")!), file: file)
        writer.add(kept, startTerminal: false)
        writer.selectedID = kept.id
        writer.saveNow()

        let store = SessionStore(settings: AppSettings(defaults: UserDefaults(suiteName: "r-\(UUID())")!), file: file)
        store.restore()
        #expect(store.sessions.map(\.id) == [kept.id])
        #expect(store.sessions[0].closedAt == kept.closedAt)
        #expect(store.terminals.terminal(for: kept.id) == nil)
        #expect(store.selectedID == nil)
    }
}
