import Foundation

/// Parses a git remote URL to the GitHub repo it points at.
enum GitRemote {
    /// Handles `https://github.com/o/r(.git)`, `git@github.com:o/r(.git)`,
    /// `ssh://git@github.com(:22)/o/r(.git)` and `ssh.github.com`. Nil for
    /// non-GitHub remotes.
    static func gitHubRepo(fromRemoteURL raw: String) -> GitHubRepoRef? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostAndPath: (host: String, path: String)
        if text.contains("://") {
            guard let url = URL(string: text), let host = url.host else { return nil }
            hostAndPath = (host, url.path)
        } else if let colon = text.firstIndex(of: ":"), !text[..<colon].contains("/") {
            // scp-like: [user@]host:path
            let hostPart = text[..<colon]
            let host = hostPart.split(separator: "@").last.map(String.init) ?? String(hostPart)
            hostAndPath = (host, String(text[text.index(after: colon)...]))
        } else {
            return nil
        }
        let host = hostAndPath.host.lowercased()
        guard ["github.com", "www.github.com", "ssh.github.com"].contains(host) else { return nil }
        var parts = hostAndPath.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return GitHubRepoRef(owner: parts[0], name: parts[1])
    }
}
