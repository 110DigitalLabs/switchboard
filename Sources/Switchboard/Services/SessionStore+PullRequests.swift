import Foundation

extension SessionStore {
    /// Links PRs to a row, skipping ones it already has.
    func attachPullRequests(_ urls: [String], to id: UUID) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        let known = Set(session.prURLs.map { PullRequestReference(url: $0)?.url ?? $0 })
        var seen = known
        let added = urls.map { PullRequestReference(url: $0)?.url ?? $0 }.filter { seen.insert($0).inserted }
        guard !added.isEmpty else { return }
        session.prURLs += added
        update(session)
        onPullRequestSourcesChanged?()
    }

    /// Discovered repos' GitHub origins, keyed by repo path.
    func repoOrigins(using git: GitInfo = GitInfo()) async -> [String: GitHubRepoRef] {
        await withTaskGroup(of: (String, GitHubRepoRef?).self) { group in
            for repo in repos {
                group.addTask { (repo.url.path, await git.originRepo(in: repo.url.path)) }
            }
            var origins: [String: GitHubRepoRef] = [:]
            for await (path, origin) in group {
                if let origin { origins[path] = origin }
            }
            return origins
        }
    }

    /// Starts a session for reviewing a PR without checking it out, with
    /// "Review <url> " typed but not submitted.
    func startReviewSession(_ ref: PullRequestReference, pullRequest: PullRequest?, folder: ReviewFolder,
                            agent: Agent, startTerminal: Bool = true) {
        if case .temp(let url) = folder {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                errorMessage = "Could not create the review folder: \(error.localizedDescription)"
                return
            }
        }
        let session = ReviewSessions.newSession(for: ref, folder: folder, agent: agent, pullRequest: pullRequest,
                                                teamKeys: ticketSource?.teamKeys ?? [])
        add(session, startTerminal: startTerminal, draft: ReviewSessions.draft(for: ref))
        if let ticket = session.ticketID { loadTicketDetails(ticket, rowID: session.id) }
        onPullRequestSourcesChanged?()
    }
}
