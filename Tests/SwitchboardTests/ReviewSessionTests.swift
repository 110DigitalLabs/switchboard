import Foundation
import Testing
@testable import Switchboard

struct ReviewSessionTests {
    private let home = URL(fileURLWithPath: "/home")
    private let ref = PullRequestReference(repo: GitHubRepoRef(owner: "Acme", name: "api"), number: 42)
    private let api = Repo(url: URL(fileURLWithPath: "/home/work/api"), relativePath: "work/api")
    private let web = Repo(url: URL(fileURLWithPath: "/home/web"), relativePath: "web")

    @Test func localCloneMatchedByOriginIsUsed() {
        let origins = ["/home/web": GitHubRepoRef(owner: "acme", name: "web"),
                       "/home/work/api": GitHubRepoRef(owner: "acme", name: "API")]
        #expect(ReviewSessions.folder(for: ref, repos: [web, api], origins: origins, home: home) == .repo(api))
    }

    @Test func otherwiseAReviewFolder() {
        let origins = ["/home/work/api": GitHubRepoRef(owner: "someone-else", name: "api")]
        let folder = ReviewSessions.folder(for: ref, repos: [api], origins: origins, home: home)
        #expect(folder == .temp(URL(fileURLWithPath: "/home/reviews/Acme-api-42", isDirectory: true)))
    }

    @Test func repoSessionIsPlainFolderNeverWorktree() {
        let session = ReviewSessions.newSession(for: ref, folder: .repo(api), agent: .claudeCode,
                                                pullRequest: nil, teamKeys: [])
        #expect(session.kind == .folder && session.folderPath == "/home/work/api")
        #expect(session.prURLs == ["https://github.com/Acme/api/pull/42"])
        #expect(session.ticketID == nil)
        #expect(session.launchCommand(hooks: nil)?.contains("-w") == false)
    }

    @Test func tempSessionGetsReviewIcon() {
        let session = ReviewSessions.newSession(for: ref, folder: .temp(ReviewSessions.tempFolder(for: ref, in: home)),
                                                agent: .codex, pullRequest: nil, teamKeys: [])
        #expect(session.kind == .temp)
        #expect(session.iconName == "eye")
        #expect(TicketTestSupport.session(.temp, path: "/home/tickets/ENG-1").iconName == "clock")
    }

    @Test func ticketFromTitleThenBranch() {
        let keys: Set<String> = ["ENG"]
        #expect(ReviewSessions.ticket(for: GitHubFixtures.pr(1, title: "ENG-12: fix login", head: "x"), teamKeys: keys) == "ENG-12")
        #expect(ReviewSessions.ticket(for: GitHubFixtures.pr(1, title: "Fix login", head: "ada/eng-7-login"), teamKeys: keys) == "ENG-7")
        #expect(ReviewSessions.ticket(for: GitHubFixtures.pr(1, title: "UTF-8 fix", head: "utf-8"), teamKeys: keys) == nil)
        #expect(ReviewSessions.ticket(for: nil, teamKeys: keys) == nil)
    }

    @Test func draftIsTypedWithCursorAfterTheLink() {
        #expect(ReviewSessions.draft(for: ref) == "Review https://github.com/Acme/api/pull/42 ")
        #expect(TypedText.sanitize(ReviewSessions.draft(for: ref)) == ReviewSessions.draft(for: ref))
    }

    @MainActor
    @Test func startingCreatesTheFolderAndTagsTheTicket() throws {
        let home = TicketTestSupport.tempDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TicketTestSupport.store(home: home)
        let source = StubTicketSource(teamKeys: ["ENG"], isConnected: false)
        store.ticketSource = source
        let folder = ReviewSessions.tempFolder(for: ref, in: home)
        store.startReviewSession(ref, pullRequest: GitHubFixtures.pr(42, title: "ENG-3 review me"),
                                 folder: .temp(folder), agent: .claudeCode, startTerminal: false)
        #expect(SessionLaunch.directoryExists(folder.path))
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].ticketID == "ENG-3")
        #expect(store.sessions[0].prURLs == [ref.url])
    }
}
