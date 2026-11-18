import Foundation
@testable import Switchboard

/// In-memory GitHubService that records its calls.
actor FakeGitHubService: GitHubService {
    var status: GitHubAvailability
    var prs: [String: PullRequest]
    var branchPRs: [String: [PullRequest]]
    var nextError: GitHubError?
    private(set) var viewed: [String] = []
    private(set) var listed: [String] = []

    init(status: GitHubAvailability = .available(login: "octo"), prs: [PullRequest] = [],
         branchPRs: [String: [PullRequest]] = [:]) {
        self.status = status
        self.prs = Dictionary(uniqueKeysWithValues: prs.map { ($0.url, $0) })
        self.branchPRs = branchPRs
    }

    func fail(next error: GitHubError?) { nextError = error }
    func set(_ pr: PullRequest) { prs[pr.url] = pr }

    func availability() async -> GitHubAvailability { status }

    func pullRequest(_ ref: PullRequestReference) async throws -> PullRequest {
        viewed.append(ref.url)
        if let error = nextError { nextError = nil; throw error }
        guard let pr = prs[ref.url] else { throw GitHubError.notFound }
        return pr
    }

    func pullRequests(head branch: String, in repo: GitHubRepoRef) async throws -> [PullRequest] {
        listed.append("\(repo.slug):\(branch)")
        if let error = nextError { nextError = nil; throw error }
        return branchPRs["\(repo.slug):\(branch)"] ?? []
    }
}

struct FakeCheckouts: CheckoutInspecting {
    var branches: [String: String] = [:]
    var origins: [String: GitHubRepoRef] = [:]
    var defaults: [String: String] = [:]

    func branch(in directory: String) async -> String? { branches[directory] }
    func originRepo(in directory: String) async -> GitHubRepoRef? { origins[directory] }
    func defaultBranch(in directory: String) async -> String? { defaults[directory] }
}

enum GitHubFixtures {
    static func pr(_ number: Int, repo: String = "acme/api", title: String = "A change", state: PullRequest.State = .open,
                   draft: Bool = false, head: String? = "feature", owner: String? = nil) -> PullRequest {
        PullRequest(number: number, title: title, state: state, isDraft: draft,
                    url: "https://github.com/\(repo)/pull/\(number)", headRefName: head, baseRefName: "main",
                    headRepositoryOwner: owner.map { PullRequest.Owner(login: $0) })
    }

    static func data(_ text: String) -> Data { Data(text.utf8) }
}
