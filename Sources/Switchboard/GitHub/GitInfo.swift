import Foundation

/// Reads a checkout's branch and GitHub remote with /usr/bin/git.
struct GitInfo: Sendable {
    var git = "/usr/bin/git"
    var timeout: Duration = .seconds(10)

    /// The checked-out branch; nil when detached or not a repo.
    func branch(in directory: String) async -> String? {
        guard let output = await run(["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]),
              output != "HEAD" else { return nil }
        return output
    }

    /// owner/repo of `origin`, when it is on GitHub.
    func originRepo(in directory: String) async -> GitHubRepoRef? {
        guard let output = await run(["-C", directory, "remote", "get-url", "origin"]) else { return nil }
        return GitRemote.gitHubRepo(fromRemoteURL: output)
    }

    /// The branch `origin/HEAD` points at, e.g. "main".
    func defaultBranch(in directory: String) async -> String? {
        guard let output = await run(["-C", directory, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        else { return nil }
        return output.split(separator: "/", maxSplits: 1).last.map(String.init)
    }

    private func run(_ arguments: [String]) async -> String? {
        guard let output = try? await ProcessRunner.run(git, arguments, timeout: timeout),
              output.status == 0 else { return nil }
        let text = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
