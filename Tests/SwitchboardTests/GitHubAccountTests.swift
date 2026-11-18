import Foundation
import Testing
@testable import Switchboard

@MainActor
struct GitHubAccountTests {
    private func setup(service: FakeGitHubService, checkouts: FakeCheckouts = FakeCheckouts())
        -> (GitHubAccount, SessionStore) {
        let store = TicketTestSupport.store()
        let account = GitHubAccount(service: service, checkouts: checkouts)
        account.store = store
        return (account, store)
    }

    private func worktree(_ directory: String) -> Session {
        var session = Session(kind: .worktree, folderPath: "/repos/api", agent: .claudeCode)
        session.workingDirectory = directory
        return session
    }

    @Test func discoversBranchPRsAndDropsForks() async {
        let api = GitHubRepoRef(owner: "acme", name: "api")
        let ours = GitHubFixtures.pr(5, head: "feature", owner: "acme")
        let fork = GitHubFixtures.pr(6, head: "feature", owner: "stranger")
        let service = FakeGitHubService(branchPRs: ["acme/api:feature": [ours, fork]])
        let checkouts = FakeCheckouts(branches: ["/wt/a": "feature", "/wt/b": "main"],
                                      origins: ["/wt/a": api, "/wt/b": api])
        let (account, store) = setup(service: service, checkouts: checkouts)
        store.add(worktree("/wt/a"), startTerminal: false)
        store.add(worktree("/wt/b"), startTerminal: false)

        await account.refresh()
        #expect(store.sessions[0].prURLs == [ours.url])
        #expect(store.sessions[1].prURLs == [])
        #expect(account.pullRequest(for: ours.url) == ours)
        #expect(await service.listed == ["acme/api:feature"])
    }

    @Test func refreshesLinkedPRsButNotMergedOnesAgain() async {
        let merged = GitHubFixtures.pr(1, state: .merged)
        let open = GitHubFixtures.pr(2, state: .open)
        let service = FakeGitHubService(prs: [merged, open])
        let (account, store) = setup(service: service)
        var session = Session(kind: .folder, folderPath: "/x", agent: .claudeCode)
        session.prURLs = [merged.url, open.url + "/files"]
        store.add(session, startTerminal: false)

        await account.refresh()
        #expect(account.pullRequest(for: open.url)?.displayState == .open)
        #expect(account.pullRequest(for: merged.url)?.displayState == .merged)
        await service.set(GitHubFixtures.pr(2, state: .merged))
        await account.refresh()
        #expect(account.pullRequest(for: open.url)?.displayState == .merged)
        #expect(await service.viewed.filter { $0 == merged.url }.count == 1)
    }

    @Test func unavailableGitHubChangesNothing() async {
        let service = FakeGitHubService(status: .notSignedIn, prs: [GitHubFixtures.pr(1)])
        let (account, store) = setup(service: service)
        var session = Session(kind: .folder, folderPath: "/x", agent: .claudeCode)
        session.prURLs = [GitHubFixtures.pr(1).url]
        store.add(session, startTerminal: false)
        await account.refresh()
        #expect(account.availability == .notSignedIn && account.pullRequests.isEmpty)
        #expect(await service.viewed.isEmpty)
    }

    @Test func goingOfflineMidRefreshIsRecorded() async {
        let service = FakeGitHubService(prs: [GitHubFixtures.pr(1)])
        let (account, store) = setup(service: service)
        var session = Session(kind: .folder, folderPath: "/x", agent: .claudeCode)
        session.prURLs = [GitHubFixtures.pr(1).url]
        store.add(session, startTerminal: false)
        await service.fail(next: .offline)
        await account.refresh()
        #expect(account.availability == .offline && !account.isAvailable)
    }

    @Test func branchRules() {
        #expect(BranchRules.isLookupWorthy("worktree-eng-1", defaultBranch: "main"))
        #expect(!BranchRules.isLookupWorthy("main", defaultBranch: nil))
        #expect(!BranchRules.isLookupWorthy("release", defaultBranch: "release"))
    }
}
