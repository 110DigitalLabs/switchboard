import Foundation

/// Hidden debug switch: `SWITCHBOARD_FAKE_LINEAR=1` signs the app in to a
/// seeded in-memory Linear and keeps its rows in a separate sessions file,
/// so ticket flows can be exercised without a Linear account.
enum DebugLinear {
    static let environmentKey = "SWITCHBOARD_FAKE_LINEAR"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }
}

extension FakeLinearService {
    /// A workspace with assigned and unassigned issues across two teams.
    static func seeded() -> FakeLinearService {
        let eng = LinearTeam(id: "t-eng", key: "ENG", name: "Engineering")
        let ops = LinearTeam(id: "t-ops", key: "OPS", name: "Operations")
        let states = [
            LinearWorkflowState(id: "s-todo", name: "Todo", type: .unstarted),
            LinearWorkflowState(id: "s-doing", name: "In Progress", type: .started),
            LinearWorkflowState(id: "s-done", name: "Done", type: .completed),
        ]
        let me = LinearUser(id: "u1", name: "Ada Lovelace", email: "ada@example.com")
        let other = LinearUser(id: "u2", name: "Grace Hopper", email: "grace@example.com")
        let rows: [(String, LinearTeam, String, String, Int, LinearUser?)] = [
            ("ENG-101", eng, "Add Linear sign-in", "Use Linear's hosted MCP server with OAuth.", 1, me),
            ("ENG-102", eng, "Search bar accepts ticket URLs", "Detect IDs, Linear URLs and PR URLs.", 0, me),
            ("ENG-103", eng, "Worktree handover keeps the row", "Swap the new session into the same row.", 0, me),
            ("OPS-7", ops, "Rotate staging credentials", "Quarterly rotation for the staging cluster.", 0, me),
            ("ENG-120", eng, "Flaky terminal resize", "Resizing the split sometimes garbles the prompt.", 0, other),
            ("ENG-90", eng, "Ship stage 3", "Keyboard navigation and restore.", 2, me),
        ]
        let issues = rows.enumerated().map { index, row in
            LinearIssue(id: "i\(index)", identifier: row.0, title: row.2, description: row.3,
                        url: URL(string: "https://linear.app/acme/issue/\(row.0)"), state: states[row.4],
                        team: LinearTeamRef(id: row.1.id, key: row.1.key, name: row.1.name),
                        projectName: row.1.key == "ENG" ? "Switchboard" : "Infrastructure", assignee: row.5)
        }
        return FakeLinearService(user: me, issues: issues, teams: [eng, ops],
                                 states: [eng.id: states, ops.id: states])
    }
}
