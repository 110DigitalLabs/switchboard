import Testing
@testable import Switchboard

struct GitInfoTests {
    @Test func repoNameComesFromTheMainCheckout() {
        #expect(GitInfo.repoName(fromCommonDir: "/Users/me/Projects/switchboard/.git") == "switchboard")
        #expect(GitInfo.repoName(fromCommonDir: "/Users/me/Projects/switchboard/.git/") == "switchboard")
        #expect(GitInfo.repoName(fromCommonDir: "/srv/mirrors/api.git") == "api")
    }

    @Test func checkoutLabel() {
        #expect(Checkout(repo: "switchboard", branch: "main").label == "switchboard/main")
        #expect(Checkout(repo: "switchboard", branch: nil).label == "switchboard")
    }
}
