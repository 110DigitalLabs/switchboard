import Foundation

/// A GitHub pull request, decoded from `gh pr view/list --json`.
struct PullRequest: Hashable, Sendable, Decodable {
    enum State: String, Hashable, Sendable, Decodable {
        case open = "OPEN", closed = "CLOSED", merged = "MERGED", unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw.uppercased()) ?? .unknown
        }
    }

    struct Owner: Hashable, Sendable, Decodable {
        var login: String
    }

    var number: Int
    var title: String
    var state: State
    var isDraft: Bool
    var mergedAt: Date?
    var url: String
    var headRefName: String?
    var baseRefName: String?
    /// "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED"; nil when gh reports "".
    var reviewDecision: String?
    /// Only from `gh pr list`, to drop same-named branches on forks.
    var headRepositoryOwner: Owner?

    private enum CodingKeys: String, CodingKey {
        case number, title, state, isDraft, mergedAt, url, headRefName, baseRefName, reviewDecision
        case headRepositoryOwner
    }

    init(number: Int, title: String, state: State, isDraft: Bool = false, mergedAt: Date? = nil,
         url: String, headRefName: String? = nil, baseRefName: String? = nil,
         reviewDecision: String? = nil, headRepositoryOwner: Owner? = nil) {
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.mergedAt = mergedAt
        self.url = url
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.reviewDecision = reviewDecision
        self.headRepositoryOwner = headRepositoryOwner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        state = (try? c.decode(State.self, forKey: .state)) ?? .unknown
        isDraft = (try? c.decodeIfPresent(Bool.self, forKey: .isDraft)) ?? false
        mergedAt = (try? c.decodeIfPresent(String.self, forKey: .mergedAt)).flatMap {
            $0.flatMap { ISO8601DateFormatter().date(from: $0) }
        }
        url = try c.decode(String.self, forKey: .url)
        headRefName = try? c.decodeIfPresent(String.self, forKey: .headRefName)
        baseRefName = try? c.decodeIfPresent(String.self, forKey: .baseRefName)
        reviewDecision = (try? c.decodeIfPresent(String.self, forKey: .reviewDecision)).flatMap {
            $0.flatMap { $0.isEmpty ? nil : $0 }
        }
        headRepositoryOwner = try? c.decodeIfPresent(Owner.self, forKey: .headRepositoryOwner)
    }

    /// How the PR is drawn.
    var displayState: PullRequestDisplayState {
        switch state {
        case .merged: .merged
        case .closed: .closed
        case .open: isDraft ? .draft : .open
        case .unknown: mergedAt != nil ? .merged : .unknown
        }
    }

    /// "#123 title", the icon's tooltip.
    var label: String { title.isEmpty ? "#\(number)" : "#\(number) \(title)" }

    /// The `--json` fields Switchboard asks gh for.
    static let viewFields = "number,title,state,mergedAt,isDraft,url,headRefName,baseRefName,reviewDecision"
    static let listFields = viewFields + ",headRepositoryOwner"
}

/// What a PR icon shows. `unknown` is a linked PR whose state has not
/// loaded (or GitHub is unavailable).
enum PullRequestDisplayState: Hashable, Sendable {
    case open, draft, closed, merged, unknown

    var symbolName: String {
        switch self {
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .open, .draft, .unknown: "arrow.triangle.pull"
        }
    }

    var accessibilityName: String {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .closed: "Closed"
        case .merged: "Merged"
        case .unknown: "Pull request"
        }
    }
}
