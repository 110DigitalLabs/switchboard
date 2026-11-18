import Foundation
import Testing
@testable import Switchboard

/// Records calls and answers them from a script.
actor ScriptedCaller: MCPToolCalling {
    let tools: [MCPTool]
    var replies: [String: MCPToolResult]
    var error: Error?
    private(set) var calls: [(String, [String: JSONValue])] = []

    init(tools: [MCPTool], replies: [String: MCPToolResult]) {
        self.tools = tools
        self.replies = replies
    }

    func listTools() async throws -> [MCPTool] {
        if let error { throw error }
        return tools
    }

    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        calls.append((name, arguments))
        if let error { throw error }
        return replies[name] ?? LinearFixtures.text("{}")
    }

    func arguments(of name: String) -> [String: JSONValue]? { calls.last { $0.0 == name }?.1 }
    func fail(with error: Error) { self.error = error }
}

struct MCPLinearServiceTests {
    static let currentTools = [
        LinearFixtures.tool("list_issues", ["assignee", "query", "limit", "includeArchived", "cursor"]),
        LinearFixtures.tool("get_issue", ["id"]),
        LinearFixtures.tool("list_issue_statuses", ["team"]),
        LinearFixtures.tool("list_teams", ["limit"]),
        LinearFixtures.tool("get_user", ["query"]),
        LinearFixtures.tool("save_issue", ["id", "state", "title"]),
    ]

    static func caller(tools: [MCPTool] = currentTools) -> ScriptedCaller {
        ScriptedCaller(tools: tools, replies: [
            "list_issues": LinearFixtures.text(LinearFixtures.listIssues),
            "get_issue": LinearFixtures.text(LinearFixtures.getIssue),
            "list_issue_statuses": LinearFixtures.text(LinearFixtures.statuses),
            "list_teams": LinearFixtures.text(LinearFixtures.teams),
            "get_user": LinearFixtures.text(LinearFixtures.user),
        ])
    }

    @Test func assignedIssuesAreOpenAndEnrichedWithStateIDs() async throws {
        let caller = Self.caller()
        let issues = try await MCPLinearService(caller: caller).myAssignedIssues()
        #expect(issues.map(\.identifier) == ["ENG-123"])
        #expect(issues[0].state == LinearWorkflowState(id: "s3", name: "In Progress", type: .started))
        let args = try #require(await caller.arguments(of: "list_issues"))
        #expect(args["assignee"] == "me")
        #expect(args["limit"] == 100)
        #expect(await caller.arguments(of: "list_issue_statuses")?["team"] == "t1")
    }

    @Test func issueLookupAcceptsURLsAndMapsNotFound() async throws {
        let caller = Self.caller()
        let service = MCPLinearService(caller: caller)
        let issue = try await service.issue(identifier: "https://linear.app/acme/issue/ops-7/rotate-keys")
        #expect(issue.identifier == "OPS-7")
        #expect(await caller.arguments(of: "get_issue")?["id"] == "OPS-7")

        await #expect(throws: LinearError.invalidReference("hello")) { try await service.issue(identifier: "hello") }
        let missing = ScriptedCaller(tools: Self.currentTools,
                                     replies: ["get_issue": LinearFixtures.text("Entity not found: Issue", isError: true)])
        await #expect(throws: LinearError.notFound) {
            try await MCPLinearService(caller: missing).issue(identifier: "ENG-404")
        }
    }

    @Test func setStateUsesWhicheverToolAndArgumentTheServerHas() async throws {
        let current = Self.caller()
        try await MCPLinearService(caller: current).setState(issueID: "i1", stateID: "s3")
        #expect(await current.arguments(of: "save_issue") == ["id": "i1", "state": "s3"])

        let legacy = Self.caller(tools: [LinearFixtures.tool("update_issue", ["id", "stateId"])])
        try await MCPLinearService(caller: legacy).setState(issueID: "i1", stateID: "s3")
        #expect(await legacy.arguments(of: "update_issue") == ["id": "i1", "stateId": "s3"])
    }

    @Test func teamsUserAndSearch() async throws {
        let caller = Self.caller()
        let service = MCPLinearService(caller: caller)
        #expect(try await service.teamKeys() == ["ENG", "OPS"])
        #expect(try await service.currentUser().name == "Ada Lovelace")
        #expect(await caller.arguments(of: "get_user") == ["query": "me"])
        _ = try await service.searchIssues(query: " login ")
        #expect(await caller.arguments(of: "list_issues")?["query"] == "login")
        #expect(try await service.workflowStates(teamID: "t1").count == 5)
    }

    @Test func transportErrorsBecomeLinearErrors() async {
        let caller = Self.caller()
        await caller.fail(with: MCPError.unauthorized)
        await #expect(throws: LinearError.signedOut) { try await MCPLinearService(caller: caller).myAssignedIssues() }
        let offline = Self.caller()
        await offline.fail(with: URLError(.notConnectedToInternet))
        await #expect(throws: LinearError.offline) { try await MCPLinearService(caller: offline).teams() }
    }

    @Test func missingToolIsReported() async {
        let service = MCPLinearService(caller: Self.caller(tools: []))
        await #expect(throws: LinearError.toolMissing("get_issue")) { try await service.issue(identifier: "ENG-1") }
    }
}
