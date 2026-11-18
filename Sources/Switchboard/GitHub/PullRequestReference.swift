import Foundation

/// owner/repo on GitHub.
struct GitHubRepoRef: Hashable, Sendable {
    var owner: String
    var name: String

    var slug: String { "\(owner)/\(name)" }

    func matches(_ other: GitHubRepoRef) -> Bool {
        owner.caseInsensitiveCompare(other.owner) == .orderedSame
            && name.caseInsensitiveCompare(other.name) == .orderedSame
    }
}

/// A PR identified by its URL.
struct PullRequestReference: Hashable, Sendable {
    var repo: GitHubRepoRef
    var number: Int

    /// The canonical `https://github.com/<owner>/<repo>/pull/<n>`.
    var url: String { "https://github.com/\(repo.owner)/\(repo.name)/pull/\(number)" }

    init(repo: GitHubRepoRef, number: Int) {
        self.repo = repo
        self.number = number
    }

    init?(url: String) {
        guard let match = Self.find(in: url).first else { return nil }
        self = match
    }

    /// Every distinct PR URL in free text, in order, canonicalised (so
    /// `…/pull/7/files` and `…/pull/7` are the same PR).
    static func find(in text: String) -> [PullRequestReference] {
        var seen = Set<PullRequestReference>()
        var found: [PullRequestReference] = []
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            guard let owner = Range(match.range(at: 1), in: text),
                  let name = Range(match.range(at: 2), in: text),
                  let number = Range(match.range(at: 3), in: text),
                  let value = Int(text[number]), value > 0 else { continue }
            let ref = PullRequestReference(repo: GitHubRepoRef(owner: String(text[owner]), name: String(text[name])),
                                           number: value)
            if seen.insert(ref).inserted { found.append(ref) }
        }
        return found
    }

    private static let pattern = try! NSRegularExpression(
        pattern: "https?://(?:www\\.)?github\\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/pull/([0-9]+)(?![0-9])",
        options: [.caseInsensitive])
}
