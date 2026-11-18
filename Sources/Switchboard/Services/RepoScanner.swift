import Foundation

/// Finds git repos at most two levels below the home folder.
enum RepoScanner {
    /// Top-level folders Switchboard owns or that never hold user repos.
    static let skippedTopLevel: Set<String> = ["node_modules", "scratch", "tickets"]
    static let skippedNested: Set<String> = ["node_modules"]

    /// `.git` is a directory in a normal clone and a file in a worktree.
    static func isGitRepo(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    static func scan(home: URL) -> [Repo] {
        let home = home.standardizedFileURL
        var repos: [Repo] = []
        for first in subdirectories(of: home, skipping: skippedTopLevel) {
            if isGitRepo(first) {
                repos.append(Repo(url: first, relativePath: first.lastPathComponent))
                continue
            }
            for second in subdirectories(of: first, skipping: skippedNested) where isGitRepo(second) {
                repos.append(Repo(url: second, relativePath: "\(first.lastPathComponent)/\(second.lastPathComponent)"))
            }
        }
        return repos.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func subdirectories(of url: URL, skipping skipped: Set<String>) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { child in
            let name = child.lastPathComponent
            guard !name.hasPrefix("."), !skipped.contains(name) else { return false }
            let values = try? child.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }
}
