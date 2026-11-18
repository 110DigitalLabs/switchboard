import Foundation

/// In-memory LinearService for tests and previews.
actor FakeLinearService: LinearService {
    var user: LinearUser
    var issues: [LinearIssue]
    var teamList: [LinearTeam]
    var states: [String: [LinearWorkflowState]]
    /// Thrown by the next call, then cleared.
    var nextError: LinearError?
    private(set) var assignedFetches = 0
    private(set) var stateFetches = 0

    init(user: LinearUser = LinearUser(id: "u1", name: "Ada Lovelace", email: "ada@example.com"),
         issues: [LinearIssue] = [], teams: [LinearTeam] = [], states: [String: [LinearWorkflowState]] = [:]) {
        self.user = user
        self.issues = issues
        self.teamList = teams
        self.states = states
    }

    func fail(next error: LinearError?) { nextError = error }
    func setIssues(_ issues: [LinearIssue]) { self.issues = issues }

    func currentUser() async throws -> LinearUser {
        try checkError()
        return user
    }

    func myAssignedIssues() async throws -> [LinearIssue] {
        assignedFetches += 1
        try checkError()
        return issues.filter { $0.assignee?.id == user.id && $0.isOpen }
    }

    func issue(identifier: String) async throws -> LinearIssue {
        try checkError()
        guard let id = TicketReference.parse(identifier)?.linearIdentifier else {
            throw LinearError.invalidReference(identifier)
        }
        guard let issue = issues.first(where: { $0.identifier == id }) else { throw LinearError.notFound }
        return issue
    }

    func searchIssues(query: String) async throws -> [LinearIssue] {
        try checkError()
        let needle = query.lowercased()
        return issues.filter { $0.title.lowercased().contains(needle) || $0.identifier.lowercased().contains(needle) }
    }

    func teams() async throws -> [LinearTeam] {
        try checkError()
        return teamList
    }

    func teamKeys() async throws -> Set<String> {
        try checkError()
        return Set(teamList.map(\.key))
    }

    func workflowStates(teamID: String) async throws -> [LinearWorkflowState] {
        stateFetches += 1
        try checkError()
        return states[teamID] ?? []
    }

    func setState(issueID: String, stateID: String) async throws {
        try checkError()
        guard let index = issues.firstIndex(where: { $0.id == issueID }) else { throw LinearError.notFound }
        guard let teamID = issues[index].team.id,
              let state = states[teamID]?.first(where: { $0.id == stateID }) else {
            throw LinearError.tool("Unknown state")
        }
        issues[index].state = state
    }

    private func checkError() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}

extension FakeLinearService {
    /// A small workspace for previews.
    static func sample() -> FakeLinearService {
        let team = LinearTeam(id: "t1", key: "ENG", name: "Engineering")
        let states = [
            LinearWorkflowState(id: "s1", name: "Todo", type: .unstarted),
            LinearWorkflowState(id: "s2", name: "In Progress", type: .started),
            LinearWorkflowState(id: "s3", name: "Done", type: .completed),
        ]
        let user = LinearUser(id: "u1", name: "Ada Lovelace", email: "ada@example.com")
        let issues = [
            ("ENG-101", "Add Linear sign-in", states[1]),
            ("ENG-102", "Search bar accepts ticket URLs", states[0]),
            ("ENG-90", "Ship stage 3", states[2]),
        ].enumerated().map { index, item in
            LinearIssue(id: "i\(index)", identifier: item.0, title: item.1, description: nil,
                        url: URL(string: "https://linear.app/acme/issue/\(item.0)"), state: item.2,
                        team: LinearTeamRef(id: team.id, key: team.key, name: team.name),
                        projectName: "Switchboard", assignee: user)
        }
        return FakeLinearService(user: user, issues: issues, teams: [team], states: [team.id: states])
    }
}
