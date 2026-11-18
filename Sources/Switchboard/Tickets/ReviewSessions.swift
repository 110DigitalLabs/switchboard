import Foundation

/// Where a PR review session starts: a local clone of the PR's repo
/// (plain, no worktree), or `<home>/reviews/<owner>-<repo>-<number>`.
enum ReviewFolder: Equatable, Sendable {
    case repo(Repo)
    case temp(URL)
}

/// Pure rules for PR review sessions (no checkout).
enum ReviewSessions {
    static let folderName = "reviews"

    static func tempFolder(for ref: PullRequestReference, in home: URL) -> URL {
        home.appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(safeName("\(ref.repo.owner)-\(ref.repo.name)-\(ref.number)"), isDirectory: true)
    }

    /// The first discovered repo whose origin is the PR's repo, else a
    /// review folder. `origins` maps repo paths to their GitHub origin.
    static func folder(for ref: PullRequestReference, repos: [Repo], origins: [String: GitHubRepoRef],
                       home: URL) -> ReviewFolder {
        if let repo = repos.first(where: { origins[$0.url.path]?.matches(ref.repo) == true }) {
            return .repo(repo)
        }
        return .temp(tempFolder(for: ref, in: home))
    }

    /// A ticket the PR's title or head branch names, if any.
    static func ticket(for pr: PullRequest?, teamKeys: Set<String>) -> String? {
        guard let pr else { return nil }
        return TicketMentions.find(in: pr.title, validTeamKeys: teamKeys).first
            ?? pr.headRefName.flatMap { TicketMentions.find(in: $0, validTeamKeys: teamKeys).first }
    }

    static func newSession(for ref: PullRequestReference, folder: ReviewFolder, agent: Agent,
                           pullRequest: PullRequest?, teamKeys: Set<String>) -> Session {
        var session: Session = switch folder {
        case .repo(let repo): Session(kind: .folder, folderPath: repo.url.path, agent: agent)
        case .temp(let url): Session(kind: .temp, folderPath: url.path, agent: agent)
        }
        session.prURLs = [ref.url]
        session.ticketID = ticket(for: pullRequest, teamKeys: teamKeys)
        return session
    }

    /// Typed, not submitted: the user finishes the prompt.
    static func draft(for ref: PullRequestReference) -> String { "Review \(ref.url) " }

    /// Whether a row is a PR review in its own temp folder.
    static func isReviewFolder(_ session: Session) -> Bool {
        session.kind == .temp
            && URL(fileURLWithPath: session.folderPath).deletingLastPathComponent().lastPathComponent == folderName
    }

    private static func safeName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "-" })
    }
}
