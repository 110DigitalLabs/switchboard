import Foundation
import Testing
@testable import Switchboard

struct GHJSONTests {
    @Test func decodesPRView() throws {
        // Real `gh pr view https://github.com/cli/cli/pull/1 --json …` output.
        let json = """
        {"baseRefName":"prototype","headRefName":"gh-pr","isDraft":false,"mergedAt":"2019-10-04T16:01:04Z","number":1,"reviewDecision":"","state":"MERGED","title":"interactive pr list","url":"https://github.com/cli/cli/pull/1"}
        """
        let pr = try GHJSON.pullRequest(from: GitHubFixtures.data(json))
        #expect(pr.number == 1 && pr.title == "interactive pr list" && pr.state == .merged)
        #expect(pr.mergedAt == ISO8601DateFormatter().date(from: "2019-10-04T16:01:04Z"))
        #expect(pr.reviewDecision == nil && pr.headRefName == "gh-pr" && pr.baseRefName == "prototype")
        #expect(pr.label == "#1 interactive pr list")
    }

    @Test func decodesPRListWithOwners() throws {
        let json = """
        [{"baseRefName":"main","headRefName":"feat","headRepositoryOwner":{"id":"X","login":"acme"},"isDraft":true,"mergedAt":null,"number":15,"reviewDecision":"REVIEW_REQUIRED","state":"OPEN","title":"Draft work","url":"https://github.com/acme/api/pull/15"}]
        """
        let prs = try GHJSON.pullRequests(from: GitHubFixtures.data(json))
        #expect(prs.count == 1)
        #expect(prs[0].isDraft && prs[0].mergedAt == nil && prs[0].reviewDecision == "REVIEW_REQUIRED")
        #expect(prs[0].headRepositoryOwner?.login == "acme")
        #expect(prs[0].displayState == .draft)
    }

    @Test func toleratesUnknownStateAndRejectsGarbage() throws {
        let pr = try GHJSON.pullRequest(from: GitHubFixtures.data(
            #"{"number":2,"state":"WEIRD","url":"https://github.com/a/b/pull/2"}"#))
        #expect(pr.state == .unknown && pr.title == "" && pr.label == "#2")
        #expect(throws: GitHubError.self) { try GHJSON.pullRequest(from: GitHubFixtures.data("not json")) }
    }

    @Test func authStatusLogin() {
        let signedIn = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"octo"}]}}"#
        #expect(GHJSON.activeLogin(fromAuthStatus: GitHubFixtures.data(signedIn)) == "octo")
        #expect(GHJSON.activeLogin(fromAuthStatus: GitHubFixtures.data(#"{"hosts":{}}"#)) == nil)
        let failed = #"{"hosts":{"github.com":[{"state":"error","active":true,"login":"octo"}]}}"#
        #expect(GHJSON.activeLogin(fromAuthStatus: GitHubFixtures.data(failed)) == nil)
    }

    @Test func classifiesGHErrors() {
        #expect(GitHubError.fromGH(stderr: "To get started with GitHub CLI, please run:  gh auth login", status: 4) == .notSignedIn)
        #expect(GitHubError.fromGH(stderr: "GraphQL: Could not resolve to a PullRequest with the number of 9.", status: 1) == .notFound)
        #expect(GitHubError.fromGH(stderr: "Post \"https://api.github.com/graphql\": dial tcp: lookup api.github.com: no such host", status: 1) == .offline)
        #expect(GitHubError.fromGH(stderr: "", status: 2) == .failed("gh exited with status 2"))
    }
}
