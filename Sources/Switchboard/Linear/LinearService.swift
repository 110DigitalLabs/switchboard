import Foundation

/// Everything the app asks of Linear. All methods throw `LinearError`.
protocol LinearService: Sendable {
    func currentUser() async throws -> LinearUser
    /// Open issues assigned to the signed-in user.
    func myAssignedIssues() async throws -> [LinearIssue]
    /// Any issue the user can access, by "XYZ-123" or a Linear issue URL.
    /// Throws `.notFound` or `.invalidReference`.
    func issue(identifier: String) async throws -> LinearIssue
    func searchIssues(query: String) async throws -> [LinearIssue]
    func teams() async throws -> [LinearTeam]
    /// Upper-cased team keys, for validating IDs found in prompts.
    func teamKeys() async throws -> Set<String>
    /// The team's states in Linear's order.
    func workflowStates(teamID: String) async throws -> [LinearWorkflowState]
    func setState(issueID: String, stateID: String) async throws
}
