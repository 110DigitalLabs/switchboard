import Foundation
import Observation

/// The status bar's ticket status toggle: the ticket's current state and
/// its team's workflow states (cached per team). Changes are only ever
/// made by the user picking a state.
@MainActor
@Observable
final class TicketStatusModel {
    /// Ticket ID → latest issue.
    private(set) var issues: [String: LinearIssue] = [:]
    /// Team ID → workflow states in Linear's order.
    private(set) var statesByTeam: [String: [LinearWorkflowState]] = [:]
    /// Ticket ID whose state change is in flight.
    private(set) var updating: String?
    private(set) var errorMessage: String?

    func issue(_ ticketID: String) -> LinearIssue? { issues[ticketID.uppercased()] }

    func states(for ticketID: String) -> [LinearWorkflowState] {
        issue(ticketID).flatMap { $0.team.id }.flatMap { statesByTeam[$0] } ?? []
    }

    /// Whether `state` is the ticket's current one (by ID, else by name).
    func isCurrent(_ state: LinearWorkflowState, for ticketID: String) -> Bool {
        guard let current = issue(ticketID)?.state else { return false }
        if let id = current.id, let other = state.id { return id == other }
        return current.name == state.name
    }

    /// Loads the issue, and its team's states unless cached.
    func load(_ ticketID: String, service: LinearService) async {
        do {
            let issue = try await service.issue(identifier: ticketID)
            issues[ticketID.uppercased()] = issue
            if let teamID = issue.team.id, statesByTeam[teamID] == nil {
                statesByTeam[teamID] = try await service.workflowStates(teamID: teamID)
            }
            errorMessage = nil
        } catch {
            errorMessage = LinearError(error).localizedDescription
        }
    }

    /// Sets the ticket's state, then reloads the issue from Linear.
    func setState(_ state: LinearWorkflowState, for ticketID: String, service: LinearService) async {
        guard let issue = issue(ticketID), let stateID = state.id, updating == nil else { return }
        updating = ticketID
        defer { updating = nil }
        do {
            try await service.setState(issueID: issue.id, stateID: stateID)
            await load(ticketID, service: service)
        } catch {
            errorMessage = LinearError(error).localizedDescription
        }
    }
}
