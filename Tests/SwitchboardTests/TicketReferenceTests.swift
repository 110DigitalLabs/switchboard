import Foundation
import Testing
@testable import Switchboard

struct TicketReferenceTests {
    @Test(arguments: [("ENG-123", "ENG-123"), ("eng-42", "ENG-42"), ("  Ab2-7\n", "AB2-7")])
    func parsesLinearIDs(input: String, expected: String) {
        #expect(TicketReference.parse(input) == .linearID(expected))
    }

    @Test func parsesLinearURLs() throws {
        let ref = try #require(TicketReference.parse("https://linear.app/acme/issue/eng-123/add-sign-in"))
        #expect(ref.linearIdentifier == "ENG-123")
        guard case .linearURL(_, let url) = ref else { Issue.record("wrong case"); return }
        #expect(url.host == "linear.app")
        #expect(TicketReference.parse("linear.app/acme/issue/ENG-9")?.linearIdentifier == "ENG-9")
    }

    @Test func parsesGitHubPullRequests() {
        let ref = TicketReference.parse("https://github.com/apple/swift/pull/7123/files?diff=split")
        guard case .githubPullRequest(let owner, let repo, let number, _) = ref else {
            Issue.record("expected PR, got \(String(describing: ref))"); return
        }
        #expect(owner == "apple")
        #expect(repo == "swift")
        #expect(number == 7123)
        #expect(ref?.linearIdentifier == nil)
        if case .githubPullRequest(_, _, 5, _) = TicketReference.parse("www.github.com/a/b/pull/5") {} else {
            Issue.record("bare www host not parsed")
        }
    }

    @Test(arguments: [
        "", "ENG", "123", "E-1", "-ENG-1", "ENG-12a", "ENG 123", "hello world",
        "https://linear.app/acme/project/foo", "https://github.com/a/b/issues/3",
        "https://github.com/a/b/pull/x", "https://example.com/acme/issue/ENG-1", "ftp://linear.app/a/issue/ENG-1",
    ])
    func rejectsOtherText(input: String) {
        #expect(TicketReference.parse(input) == nil)
    }
}

struct TicketMentionsTests {
    let keys: Set<String> = ["ENG", "OPS"]

    @Test func findsKnownKeysInOrderWithoutDuplicates() {
        let text = "let's work on eng-12 then OPS-7, and ENG-12 again (see https://linear.app/x/issue/ENG-3/y)"
        #expect(TicketMentions.find(in: text, validTeamKeys: keys) == ["ENG-12", "OPS-7", "ENG-3"])
    }

    @Test func ignoresUnknownKeysAndEmbeddedMatches() {
        let text = "UTF-8 and GPT-4 and ISO-8601, xENG-1, ENG-1x, ENG-2_3, PRE-ENG-4"
        #expect(TicketMentions.find(in: text, validTeamKeys: keys) == [])
    }

    @Test func noKeysMeansNoMatches() {
        #expect(TicketMentions.find(in: "ENG-1", validTeamKeys: []) == [])
    }

    @Test func keysMatchCaseInsensitively() {
        #expect(TicketMentions.find(in: "ENG-5", validTeamKeys: ["eng"]) == ["ENG-5"])
    }
}
