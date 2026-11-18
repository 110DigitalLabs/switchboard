import Foundation
import Testing
@testable import Switchboard

struct RepoScannerTests {
    private let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    private func makeDir(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    private func makeFile(_ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gitdir: elsewhere\n".utf8).write(to: url)
    }

    @Test func findsReposOneAndTwoLevelsDown() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir("alpha/.git")
        try makeDir("work/beta/.git")
        try makeFile("work/linked/.git") // worktree: .git is a file
        try makeDir("work/plain")
        try makeDir("deep/a/b/.git") // three levels: ignored

        let repos = RepoScanner.scan(home: home).map(\.relativePath)
        #expect(repos == ["alpha", "work/beta", "work/linked"])
    }

    @Test func skipsHiddenNodeModulesAndAppFolders() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir(".hidden/.git")
        try makeDir("node_modules/pkg/.git")
        try makeDir("work/node_modules/.git")
        try makeDir("work/.cache/.git")
        try makeDir("scratch/20260101-000000/.git")
        try makeDir("tickets/XYZ-1/.git")
        try makeDir("real/.git")

        #expect(RepoScanner.scan(home: home).map(\.relativePath) == ["real"])
    }

    @Test func doesNotDescendIntoRepos() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir("outer/.git")
        try makeDir("outer/inner/.git")

        #expect(RepoScanner.scan(home: home).map(\.relativePath) == ["outer"])
    }

    @Test func missingHomeYieldsNothing() {
        #expect(RepoScanner.scan(home: home.appendingPathComponent("nope")).isEmpty)
        try? FileManager.default.removeItem(at: home)
    }
}
