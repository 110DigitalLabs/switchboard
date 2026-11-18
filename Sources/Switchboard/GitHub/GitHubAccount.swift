import AppKit
import Observation

/// The app's GitHub connection: availability, the PR details cache, and a
/// coalesced background poll (about every 2 minutes while the app is
/// active, every 10 in the background) that refreshes linked PRs and finds
/// PRs for worktree sessions' branches.
@MainActor
@Observable
final class GitHubAccount {
    /// Nil until the first check finishes.
    private(set) var availability: GitHubAvailability?
    /// Canonical PR URL → latest details.
    private(set) var pullRequests: [String: PullRequest] = [:]
    private(set) var lastRefreshed: Date?

    var isAvailable: Bool { availability?.isAvailable ?? false }

    let service: GitHubService
    @ObservationIgnored let checkouts: CheckoutInspecting
    @ObservationIgnored weak var store: SessionStore?
    @ObservationIgnored var isAppActive: () -> Bool = { NSApp?.isActive ?? false }
    @ObservationIgnored let activeInterval: Duration
    @ObservationIgnored let backgroundInterval: Duration
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// Worktree directory → origin repo and default branch; neither changes.
    @ObservationIgnored private var origins: [String: (repo: GitHubRepoRef?, defaultBranch: String?)] = [:]

    init(service: GitHubService, checkouts: CheckoutInspecting = GitInfo(),
         activeInterval: Duration = .seconds(120), backgroundInterval: Duration = .seconds(600)) {
        self.service = service
        self.checkouts = checkouts
        self.activeInterval = activeInterval
        self.backgroundInterval = backgroundInterval
    }

    /// Checks gh, refreshes once, then polls.
    func start() {
        requestRefresh()
        startPolling()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        }
    }

    func pullRequest(for url: String) -> PullRequest? {
        pullRequests[PullRequestReference(url: url)?.url ?? url]
    }

    func checkAvailability() async {
        availability = await service.availability()
    }

    /// Starts a refresh, or queues one more pass if one is running.
    func requestRefresh() {
        guard refreshTask == nil else {
            refreshAgain = true
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                refreshAgain = false
                await refresh()
            } while refreshAgain
            refreshTask = nil
        }
    }

    /// One pass. Visible for tests; the app goes through `requestRefresh`.
    func refresh() async {
        if !isAvailable { await checkAvailability() }
        guard isAvailable, let store else { return }
        defer { lastRefreshed = Date() }
        do {
            for session in store.sessions where session.kind == .worktree {
                let found = try await discoverPullRequests(for: session)
                if !found.isEmpty { store.attachPullRequests(found, to: session.id) }
            }
            let urls = Set(store.sessions.flatMap(\.prURLs).compactMap { PullRequestReference(url: $0) })
            for ref in urls.sorted(by: { $0.url < $1.url }) where pullRequests[ref.url]?.state != .merged {
                do {
                    cache(try await service.pullRequest(ref), for: ref.url)
                } catch GitHubError.notFound, GitHubError.timedOut, GitHubError.failed {
                    continue
                }
            }
        } catch let error as GitHubError {
            switch error {
            case .offline: availability = .offline
            case .notSignedIn: availability = .notSignedIn
            case .notInstalled: availability = .notInstalled
            default: break
            }
        } catch {}
    }

    /// PRs whose head is the worktree's branch on its GitHub origin.
    private func discoverPullRequests(for session: Session) async throws -> [String] {
        guard let directory = session.workingDirectory,
              let branch = await checkouts.branch(in: directory) else { return [] }
        let origin: (repo: GitHubRepoRef?, defaultBranch: String?)
        if let cached = origins[directory] {
            origin = cached
        } else {
            origin = (await checkouts.originRepo(in: directory), await checkouts.defaultBranch(in: directory))
            origins[directory] = origin
        }
        guard let repo = origin.repo, BranchRules.isLookupWorthy(branch, defaultBranch: origin.defaultBranch)
        else { return [] }
        let found: [PullRequest]
        do {
            found = try await service.pullRequests(head: branch, in: repo)
        } catch GitHubError.notFound, GitHubError.timedOut, GitHubError.failed {
            return []
        }
        // `--head` matches the branch name in forks too; keep the repo's own.
        let own = found.filter { pr in
            pr.headRepositoryOwner.map { $0.login.caseInsensitiveCompare(repo.owner) == .orderedSame } ?? true
        }
        var urls: [String] = []
        for pr in own {
            let url = PullRequestReference(url: pr.url)?.url ?? pr.url
            cache(pr, for: url)
            urls.append(url)
        }
        return urls
    }

    private func cache(_ pr: PullRequest, for url: String) {
        if pullRequests[url] != pr { pullRequests[url] = pr }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self.map({ $0.isAppActive() ? $0.activeInterval : $0.backgroundInterval })
                else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.requestRefresh()
            }
        }
    }

    /// After a slow background stretch, catch up as soon as the user is back.
    private func appBecameActive() {
        let seconds = Double(activeInterval.components.seconds)
        if lastRefreshed.map({ Date().timeIntervalSince($0) >= seconds }) ?? true {
            requestRefresh()
        }
    }
}
