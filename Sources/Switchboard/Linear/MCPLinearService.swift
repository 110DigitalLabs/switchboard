import Foundation

/// LinearService over Linear's hosted MCP server. Tool names and argument
/// names are looked up from `tools/list`, because the server has renamed
/// tools before (update_issue → save_issue).
actor MCPLinearService: LinearService {
    private let caller: MCPToolCalling
    private var tools: [String: MCPTool]?
    private var statesByTeam: [String: [LinearWorkflowState]] = [:]
    private var cachedTeams: [LinearTeam]?

    init(caller: MCPToolCalling) {
        self.caller = caller
    }

    func currentUser() async throws -> LinearUser {
        let tool = try await tool(["get_user", "get_viewer", "get_me"])
        let json = try await callJSON(tool, [argument(tool, ["query", "id", "user"]): "me"])
        guard let user = LinearResultParser.user(json) else { throw LinearError.unexpectedResult("no user") }
        return user
    }

    func myAssignedIssues() async throws -> [LinearIssue] {
        let issues: [LinearIssue]
        if let tool = try await optionalTool(["list_issues"]), tool.argumentNames.contains("assignee") {
            issues = try await listAll(tool, ["assignee": "me", "includeArchived": false])
        } else {
            issues = try await listAll(try await tool(["list_my_issues"]), [:])
        }
        return await enrich(issues).filter(\.isOpen)
    }

    func issue(identifier: String) async throws -> LinearIssue {
        guard let id = TicketReference.parse(identifier)?.linearIdentifier else {
            throw LinearError.invalidReference(identifier)
        }
        let tool = try await tool(["get_issue"])
        let json = try await callJSON(tool, [argument(tool, ["id", "issueId", "identifier"]): .string(id)])
        guard let issue = LinearResultParser.singleIssue(json) else { throw LinearError.notFound }
        return await enrich([issue])[0]
    }

    func searchIssues(query: String) async throws -> [LinearIssue] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tool = try await tool(["list_issues", "search_issues"])
        var arguments: [String: JSONValue] = [argument(tool, ["query", "search", "term"]): .string(trimmed)]
        if tool.argumentNames.contains("limit") { arguments["limit"] = 50 }
        return await enrich(LinearResultParser.issues(try await callJSON(tool, arguments)))
    }

    func teams() async throws -> [LinearTeam] {
        if let cachedTeams { return cachedTeams }
        let tool = try await tool(["list_teams"])
        var arguments: [String: JSONValue] = [:]
        if tool.argumentNames.contains("limit") { arguments["limit"] = 250 }
        let teams = LinearResultParser.teams(try await callJSON(tool, arguments))
        cachedTeams = teams
        return teams
    }

    func teamKeys() async throws -> Set<String> {
        var keys = Set(try await teams().map(\.key).filter { !$0.isEmpty })
        if keys.isEmpty {
            // Older servers left the key out of list_teams; fall back to
            // the keys in the user's own issue identifiers.
            keys = Set(try await myAssignedIssues().map(\.team.key))
        }
        return keys
    }

    func workflowStates(teamID: String) async throws -> [LinearWorkflowState] {
        if let cached = statesByTeam[teamID] { return cached }
        let tool = try await tool(["list_issue_statuses", "list_workflow_states"])
        let json = try await callJSON(tool, [argument(tool, ["team", "teamId"]): .string(teamID)])
        let states = LinearResultParser.workflowStates(json)
        statesByTeam[teamID] = states
        return states
    }

    func setState(issueID: String, stateID: String) async throws {
        let tool = try await tool(["save_issue", "update_issue"])
        let result = try await call(tool, ["id": .string(issueID),
                                           argument(tool, ["state", "stateId", "status"]): .string(stateID)])
        if result.isError { throw Self.error(from: result) }
    }

    // MARK: - Enrichment

    /// Fills in state IDs and types from the team's workflow states when
    /// the issue only carried a state name.
    private func enrich(_ issues: [LinearIssue]) async -> [LinearIssue] {
        var result = issues
        for index in result.indices {
            guard let state = result[index].state, state.id == nil || state.type == .unknown,
                  let teamID = await teamID(for: result[index].team),
                  let states = try? await workflowStates(teamID: teamID),
                  let match = states.first(where: { $0.name.caseInsensitiveCompare(state.name) == .orderedSame })
                    ?? states.first(where: { $0.id == state.id })
            else { continue }
            result[index].state = match
            result[index].team.id = teamID
        }
        return result
    }

    private func teamID(for team: LinearTeamRef) async -> String? {
        if let id = team.id { return id }
        guard let teams = try? await teams() else { return nil }
        return teams.first { $0.key == team.key }?.id ?? teams.first { $0.name == team.name }?.id
    }

    // MARK: - Calls

    private func listAll(_ tool: MCPTool, _ base: [String: JSONValue], maxPages: Int = 5) async throws -> [LinearIssue] {
        var arguments = base.filter { tool.argumentNames.isEmpty || tool.argumentNames.contains($0.key) }
        if tool.argumentNames.contains("limit") { arguments["limit"] = 100 }
        var issues: [LinearIssue] = []
        for _ in 0..<maxPages {
            let json = try await callJSON(tool, arguments)
            issues += LinearResultParser.issues(json)
            guard tool.argumentNames.contains("cursor"), json["hasNextPage"] == .bool(true),
                  let cursor = json["cursor"]?.nonEmptyString ?? json["nextCursor"]?.nonEmptyString
            else { break }
            arguments["cursor"] = .string(cursor)
        }
        return issues
    }

    private func callJSON(_ tool: MCPTool, _ arguments: [String: JSONValue]) async throws -> JSONValue {
        let result = try await call(tool, arguments)
        if result.isError { throw Self.error(from: result) }
        guard let json = result.json else {
            throw LinearError.unexpectedResult(String(result.text.prefix(200)))
        }
        return json
    }

    private func call(_ tool: MCPTool, _ arguments: [String: JSONValue]) async throws -> MCPToolResult {
        do {
            return try await caller.callTool(tool.name, arguments: arguments)
        } catch {
            throw LinearError(error)
        }
    }

    static func error(from result: MCPToolResult) -> LinearError {
        let text = result.text
        let lower = text.lowercased()
        if lower.contains("not found") || lower.contains("could not find") { return .notFound }
        return .tool(text.isEmpty ? "Linear reported an error" : text)
    }

    /// The first tool in `names` the server offers.
    private func tool(_ names: [String]) async throws -> MCPTool {
        guard let tool = try await optionalTool(names) else { throw LinearError.toolMissing(names[0]) }
        return tool
    }

    private func optionalTool(_ names: [String]) async throws -> MCPTool? {
        if tools == nil {
            do {
                tools = Dictionary(try await caller.listTools().map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            } catch {
                throw LinearError(error)
            }
        }
        return names.lazy.compactMap { self.tools?[$0] }.first
    }

    /// The first of `names` the tool's schema declares, or the first name
    /// when the schema lists no properties.
    private func argument(_ tool: MCPTool, _ names: [String]) -> String {
        names.first { tool.argumentNames.contains($0) } ?? names[0]
    }
}

/// The part of MCPClient the service uses, so tests can script results.
protocol MCPToolCalling: Sendable {
    func listTools() async throws -> [MCPTool]
    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult
}

extension MCPClient: MCPToolCalling {}
