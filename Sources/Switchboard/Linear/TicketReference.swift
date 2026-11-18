import Foundation

/// What the user typed or pasted into the search box.
enum TicketReference: Hashable, Sendable {
    /// "XYZ-123", normalised to upper case.
    case linearID(String)
    /// linear.app/<workspace>/issue/XYZ-123/…
    case linearURL(identifier: String, url: URL)
    /// github.com/<owner>/<repo>/pull/<n>
    case githubPullRequest(owner: String, repo: String, number: Int, url: URL)

    /// The Linear issue identifier for an ID or Linear URL.
    var linearIdentifier: String? {
        switch self {
        case .linearID(let id), .linearURL(let id, _): id
        case .githubPullRequest: nil
        }
    }

    static func parse(_ text: String) -> TicketReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = normalizedID(trimmed) { return .linearID(id) }
        return parseURL(trimmed)
    }

    /// "xyz-123" → "XYZ-123"; nil unless the whole string is an ID.
    static func normalizedID(_ text: String) -> String? {
        let upper = text.uppercased()
        let range = NSRange(upper.startIndex..., in: upper)
        return idPattern.firstMatch(in: upper, options: [.anchored], range: range)?.range == range ? upper : nil
    }

    private static let idPattern = try! NSRegularExpression(pattern: "[A-Z][A-Z0-9]+-[0-9]+")

    private static func parseURL(_ text: String) -> TicketReference? {
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "linear.app":
            guard parts.count >= 3, parts[1] == "issue", let id = normalizedID(parts[2]) else { return nil }
            return .linearURL(identifier: id, url: url)
        case "github.com":
            guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]), number > 0 else { return nil }
            return .githubPullRequest(owner: parts[0], repo: parts[1], number: number, url: url)
        default:
            return nil
        }
    }
}
