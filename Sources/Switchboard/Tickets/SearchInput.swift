import Foundation

/// What the search box holds, detected as the user types.
enum SearchInput: Equatable, Sendable {
    case empty
    /// A Linear issue ID or URL, as the normalised identifier.
    case ticket(String)
    /// A GitHub PR URL.
    case pullRequest(PullRequestReference)
    /// Anything else: a Linear text search.
    case text(String)

    static func classify(_ raw: String) -> SearchInput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        switch TicketReference.parse(text) {
        case .linearID(let id), .linearURL(let id, _): return .ticket(id)
        case .githubPullRequest(let owner, let repo, let number, _):
            return .pullRequest(PullRequestReference(repo: GitHubRepoRef(owner: owner, name: repo), number: number))
        case nil: return .text(text)
        }
    }
}

/// Where a new ticket session starts, from the repo dropdown.
enum TicketDestination: Equatable, Sendable {
    /// "None": a planning session in `<home>/tickets/<ID>`.
    case tempFolder
    case repo(Repo)

    init(repo: Repo?) {
        self = repo.map(TicketDestination.repo) ?? .tempFolder
    }
}

/// What pressing Return in the search box does.
enum SearchAction: Equatable, Sendable {
    case none
    /// Local sessions already carry the ticket: go to the first.
    case selectSession(UUID)
    case startTicket(String, TicketDestination)
    case searchText(String)
    /// A review session on the PR, with no checkout.
    case startReview(PullRequestReference)

    static func forInput(_ input: SearchInput, sessions: [Session], repo: Repo?) -> SearchAction {
        switch input {
        case .empty: return .none
        case .ticket(let id):
            if let first = TicketSessions.existing(for: id, in: sessions).first {
                return .selectSession(first.id)
            }
            return .startTicket(id, TicketDestination(repo: repo))
        case .pullRequest(let ref): return .startReview(ref)
        case .text(let query): return .searchText(query)
        }
    }
}
