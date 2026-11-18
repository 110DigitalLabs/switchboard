import SwiftUI

/// What the search results and assigned list do with a ticket.
@MainActor
struct TicketActions {
    let store: SessionStore
    let settings: AppSettings
    let linear: LinearAccount

    var destination: TicketDestination { TicketDestination(repo: settings.ticketRepo) }

    var startHelp: String {
        switch destination {
        case .tempFolder: "Plan in a new temp folder under tickets/"
        case .repo(let repo): "Start a worktree session in \(repo.relativePath)"
        }
    }

    /// Starts a new session on the issue using the repo dropdown's rule.
    func start(_ issue: LinearIssue) {
        store.startTicketSession(issue, destination: destination, agent: settings.defaultAgent)
    }

    /// Picking a ticket: go to its sessions if any exist, else start one.
    func open(_ issue: LinearIssue) {
        switch SearchAction.forInput(.ticket(issue.identifier), sessions: store.sessions, repo: settings.ticketRepo) {
        case .selectSession(let id): store.selectedID = id
        default: start(issue)
        }
    }

    /// Return in the search box. Returns true when the search was used up.
    func submit(_ search: TicketSearchModel) async -> Bool {
        switch SearchAction.forInput(search.input, sessions: store.sessions, repo: settings.ticketRepo) {
        case .selectSession(let id):
            store.selectedID = id
            return true
        case .startTicket(let id, _):
            guard linear.isConnected else { return false }
            var issue = search.fetchedIssue(id)
            if issue == nil, let service = linear.service {
                do {
                    issue = try await service.issue(identifier: id)
                } catch {
                    store.errorMessage = "Could not load \(id): \(LinearError(error).localizedDescription)"
                    return false
                }
            }
            guard let issue else { return false }
            start(issue)
            return true
        case .searchText, .pullRequestUnsupported, .none:
            return false
        }
    }
}
