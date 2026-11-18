import Foundation
import Testing
@testable import Switchboard

struct SearchInputTests {
    private let repo = Repo(url: URL(fileURLWithPath: "/home/api"), relativePath: "api")

    @Test func classifiesEachKindOfInput() {
        #expect(SearchInput.classify("  ") == .empty)
        #expect(SearchInput.classify("eng-12") == .ticket("ENG-12"))
        #expect(SearchInput.classify("https://linear.app/acme/issue/ENG-12/some-title") == .ticket("ENG-12"))
        #expect(SearchInput.classify("linear.app/acme/issue/OPS-3") == .ticket("OPS-3"))
        let pr = SearchInput.classify("https://github.com/acme/api/pull/42")
        #expect(pr == .pullRequest(URL(string: "https://github.com/acme/api/pull/42")!))
        #expect(SearchInput.classify("login bug") == .text("login bug"))
        #expect(SearchInput.classify("ENG") == .text("ENG"))
    }

    @Test func ticketWithoutSessionsStartsAtDropdownDestination() {
        #expect(SearchAction.forInput(.ticket("ENG-1"), sessions: [], repo: nil) == .startTicket("ENG-1", .tempFolder))
        #expect(SearchAction.forInput(.ticket("ENG-1"), sessions: [], repo: repo) == .startTicket("ENG-1", .repo(repo)))
    }

    @Test func ticketWithSessionsSelectsTheOldestFirst() {
        let newer = TicketTestSupport.session(ticket: "ENG-1", created: 200)
        let older = TicketTestSupport.session(ticket: "ENG-1", created: 100)
        let other = TicketTestSupport.session(ticket: "ENG-2", created: 50)
        let action = SearchAction.forInput(.ticket("ENG-1"), sessions: [newer, other, older], repo: repo)
        #expect(action == .selectSession(older.id))
    }

    @Test func textAndPullRequestsNeverStartSessions() {
        #expect(SearchAction.forInput(.text("crash"), sessions: [], repo: repo) == .searchText("crash"))
        #expect(SearchAction.forInput(.pullRequest(URL(string: "https://github.com/a/b/pull/1")!),
                                      sessions: [], repo: nil) == .pullRequestUnsupported)
        #expect(SearchAction.forInput(.empty, sessions: [], repo: nil) == SearchAction.none)
    }
}
