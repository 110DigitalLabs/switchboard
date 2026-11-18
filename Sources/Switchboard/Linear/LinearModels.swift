import Foundation

/// Linear's workflow state categories.
enum LinearStateType: String, Hashable, Sendable, CaseIterable {
    case triage, backlog, unstarted, started, completed, canceled, unknown

    init(raw: String?) {
        self = raw.flatMap { LinearStateType(rawValue: $0.lowercased()) } ?? .unknown
    }

    /// Completed and canceled issues are closed.
    var isOpen: Bool { self != .completed && self != .canceled }
}

struct LinearWorkflowState: Identifiable, Hashable, Sendable {
    /// Nil only for an issue's state when Linear reported just its name
    /// and the team's states could not be loaded to resolve it.
    var id: String?
    var name: String
    var type: LinearStateType
}

struct LinearTeam: Identifiable, Hashable, Sendable {
    var id: String
    var key: String
    var name: String
}

/// The team an issue belongs to. The key always comes from the identifier.
struct LinearTeamRef: Hashable, Sendable {
    var id: String?
    var key: String
    var name: String?
}

struct LinearUser: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var email: String?
}

struct LinearIssue: Identifiable, Hashable, Sendable {
    var id: String
    /// "XYZ-123".
    var identifier: String
    var title: String
    var description: String?
    var url: URL?
    var state: LinearWorkflowState?
    var team: LinearTeamRef
    var projectName: String?
    var assignee: LinearUser?

    var isOpen: Bool { state?.type.isOpen ?? true }
}

enum LinearError: Error, Equatable, LocalizedError {
    case signedOut
    case offline
    case notFound
    case invalidReference(String)
    case toolMissing(String)
    case tool(String)
    case unexpectedResult(String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Not signed in to Linear"
        case .offline: "Linear is unreachable"
        case .notFound: "Issue not found"
        case .invalidReference(let text): "“\(text)” is not a Linear issue ID or URL"
        case .toolMissing(let name): "Linear's MCP server has no \(name) tool"
        case .tool(let message): message
        case .unexpectedResult(let detail): "Unexpected Linear response: \(detail)"
        case .other(let message): message
        }
    }

    /// Classifies any error from the MCP, OAuth or network layers.
    init(_ error: Error) {
        switch error {
        case let error as LinearError: self = error
        case MCPError.unauthorized: self = .signedOut
        case let error as OAuthError where error.requiresSignIn: self = .signedOut
        case let error as URLError where Self.offlineCodes.contains(error.code): self = .offline
        default: self = .other(error.localizedDescription)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]
}
