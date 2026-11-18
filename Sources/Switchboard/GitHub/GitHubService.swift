import Foundation

// Why gh, not MCP (checked live, Nov 2026): GitHub's hosted MCP server at
// https://api.githubcopilot.com/mcp/ does speak MCP OAuth. Its 401 points at
// protected-resource metadata naming https://github.com/login/oauth as the
// authorization server, with PKCE S256. But that server's metadata
// (/.well-known/oauth-authorization-server/login/oauth) has no
// `registration_endpoint`, so there is no dynamic client registration:
// an MCP client needs a pre-registered GitHub OAuth/GitHub App client ID
// (or a PAT). Until Switchboard ships one, the `gh` CLI, which the user has
// already signed in to, is the working backend. An MCP backend would
// implement `GitHubService` on top of `MCPClient` and the OAuth code in MCP/.

/// Everything the app asks of GitHub.
protocol GitHubService: Sendable {
    /// Whether PR features can work, and as whom. Never throws.
    func availability() async -> GitHubAvailability
    func pullRequest(_ ref: PullRequestReference) async throws -> PullRequest
    /// PRs (any state) whose head is `branch` in `repo`, newest first.
    func pullRequests(head branch: String, in repo: GitHubRepoRef) async throws -> [PullRequest]
}

enum GitHubAvailability: Equatable, Sendable {
    case available(login: String)
    case notSignedIn
    case notInstalled
    case offline
    case error(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum GitHubError: Error, Equatable, LocalizedError {
    case notInstalled
    case notSignedIn
    case offline
    case notFound
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "The GitHub CLI (gh) is not installed"
        case .notSignedIn: "gh is not signed in to GitHub"
        case .offline: "GitHub is unreachable"
        case .notFound: "Pull request not found"
        case .timedOut: "GitHub took too long to answer"
        case .failed(let message): message
        }
    }

    /// Classifies a failed gh run from its stderr.
    static func fromGH(stderr: String, status: Int32) -> GitHubError {
        let text = stderr.lowercased()
        if status == 4 || text.contains("gh auth login") || text.contains("authentication") {
            return .notSignedIn
        }
        if text.contains("could not resolve to a pullrequest") || text.contains("not found") {
            return .notFound
        }
        let offlineHints = ["dial tcp", "no such host", "connection refused", "network is unreachable",
                            "i/o timeout", "tls handshake", "proxyconnect", "could not resolve host"]
        if offlineHints.contains(where: text.contains) { return .offline }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "gh exited with status \(status)" : String(message.suffix(300)))
    }
}
