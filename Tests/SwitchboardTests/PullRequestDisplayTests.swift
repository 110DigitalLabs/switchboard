import Testing
@testable import Switchboard

struct PullRequestDisplayTests {
    @Test func stateMapsToIcon() {
        let cases: [(PullRequest, PullRequestDisplayState, String)] = [
            (GitHubFixtures.pr(1, state: .open), .open, "arrow.triangle.pull"),
            (GitHubFixtures.pr(2, state: .open, draft: true), .draft, "arrow.triangle.pull"),
            (GitHubFixtures.pr(3, state: .closed), .closed, "xmark.circle"),
            (GitHubFixtures.pr(4, state: .merged), .merged, "arrow.triangle.merge"),
            (GitHubFixtures.pr(5, state: .unknown), .unknown, "arrow.triangle.pull"),
        ]
        for (pr, state, symbol) in cases {
            #expect(pr.displayState == state)
            #expect(pr.displayState.symbolName == symbol)
        }
        #expect(PullRequestDisplayState.merged.tint == .purple)
        #expect(PullRequestDisplayState.open.tint == .green)
        #expect(PullRequestDisplayState.closed.tint == .red)
    }

    @Test func draftThatWasMergedShowsMerged() {
        #expect(GitHubFixtures.pr(1, state: .merged, draft: true).displayState == .merged)
    }

    @Test func findsDistinctCanonicalReferences() {
        let refs = PullRequestReference.find(in: """
            https://github.com/a/b/pull/1/files and http://www.github.com/a/b/pull/1#discussion, \
            (https://github.com/c/d.e/pull/22). https://github.com/a/b/pull/123456789
            """)
        #expect(refs.map(\.url) == ["https://github.com/a/b/pull/1", "https://github.com/c/d.e/pull/22",
                                    "https://github.com/a/b/pull/123456789"])
    }
}
