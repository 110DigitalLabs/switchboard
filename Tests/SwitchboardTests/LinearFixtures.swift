import Foundation
@testable import Switchboard

/// Tool outputs shaped like Linear's MCP server: JSON inside text content,
/// with related objects flattened to names plus IDs.
enum LinearFixtures {
    static let listIssues = #"""
    {"issues":[
      {"id":"9c1e-1","identifier":"ENG-123","title":"Fix login","description":"Steps…","priority":{"value":2,"name":"High"},
       "url":"https://linear.app/acme/issue/ENG-123/fix-login","gitBranchName":"ada/eng-123-fix-login",
       "createdAt":"2026-11-01T10:00:00.000Z","updatedAt":"2026-11-02T10:00:00.000Z","archivedAt":null,"completedAt":null,
       "dueDate":null,"status":"In Progress","labels":["Bug"],"attachments":[],"documents":[],
       "createdBy":"Ada Lovelace","createdById":"u1","assignee":"Ada Lovelace","assigneeId":"u1",
       "project":"Switchboard","projectId":"p1","team":"Engineering","teamId":"t1"},
      {"id":"9c1e-2","identifier":"ENG-99","title":"Old thing","description":null,
       "url":"https://linear.app/acme/issue/ENG-99/old-thing","status":"Done","assignee":"Ada Lovelace","assigneeId":"u1",
       "project":null,"team":"Engineering","teamId":"t1"}
    ],"hasNextPage":false,"cursor":null}
    """#

    static let getIssue = #"""
    {"id":"9c1e-3","identifier":"OPS-7","title":"Rotate keys","description":"",
     "url":"https://linear.app/acme/issue/OPS-7/rotate-keys",
     "state":{"id":"o2","name":"Todo","type":"unstarted"},
     "team":{"id":"t2","key":"OPS","name":"Operations"},"project":{"id":"p9","name":"Security"},
     "assignee":{"id":"u2","name":"Grace Hopper","email":"grace@example.com"}}
    """#

    static let statuses = #"""
    [{"id":"s4","type":"completed","name":"Done"},{"id":"s1","type":"backlog","name":"Backlog"},
     {"id":"s3","type":"started","name":"In Progress"},{"id":"s2","type":"unstarted","name":"Todo"},
     {"id":"s5","type":"canceled","name":"Canceled"}]
    """#

    static let teams = #"""
    [{"id":"t1","name":"Engineering","key":"ENG","icon":null},{"id":"t2","name":"Operations","key":"ops"}]
    """#

    static let user = #"""
    {"id":"u1","name":"Ada Lovelace","displayName":"ada","email":"ada@example.com","isAdmin":false,"active":true}
    """#

    static func text(_ json: String, isError: Bool = false) -> MCPToolResult {
        MCPToolResult(content: [["type": "text", "text": .string(json)]], isError: isError)
    }

    static func json(_ text: String) -> JSONValue {
        try! JSONValue(data: Data(text.utf8))
    }

    static func tool(_ name: String, _ arguments: [String]) -> MCPTool {
        MCPTool(name: name, inputSchema: .object(["type": "object", "properties": .object(
            Dictionary(uniqueKeysWithValues: arguments.map { ($0, ["type": "string"]) }))]))
    }
}
