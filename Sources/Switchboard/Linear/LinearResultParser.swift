import Foundation

/// Turns Linear MCP tool output into models. The server returns JSON as
/// text whose exact shape has changed over time (bare arrays or wrapped
/// lists; state as a name or an object), so every field is optional and
/// several spellings are accepted.
enum LinearResultParser {
    static func issues(_ json: JSONValue) -> [LinearIssue] {
        records(in: json, preferring: ["issues", "nodes", "items", "results", "data"]).compactMap(issue)
    }

    /// A single issue, bare or wrapped in `issue`.
    static func singleIssue(_ json: JSONValue) -> LinearIssue? {
        if let issue = issue(json) { return issue }
        if let wrapped = json["issue"] ?? json["data"] { return singleIssue(wrapped) }
        return issues(json).first
    }

    static func issue(_ json: JSONValue) -> LinearIssue? {
        guard json.objectValue != nil else { return nil }
        let url = json["url"]?.nonEmptyString.flatMap(URL.init(string:))
        guard let identifier = json["identifier"]?.nonEmptyString.flatMap(TicketReference.normalizedID)
                ?? url.flatMap({ TicketReference.parse($0.absoluteString)?.linearIdentifier }),
              let id = json["id"]?.nonEmptyString else { return nil }
        let key = String(identifier.prefix { $0 != "-" })
        return LinearIssue(
            id: id,
            identifier: identifier,
            title: json["title"]?.stringValue ?? "",
            description: json["description"]?.nonEmptyString,
            url: url,
            state: issueState(json),
            team: teamRef(json, key: key),
            projectName: name(of: json["project"]) ?? json["projectName"]?.nonEmptyString,
            assignee: assignee(json))
    }

    static func teams(_ json: JSONValue) -> [LinearTeam] {
        records(in: json, preferring: ["teams", "nodes", "items", "results", "data"]).compactMap { team in
            guard let id = team["id"]?.nonEmptyString else { return nil }
            return LinearTeam(id: id, key: team["key"]?.nonEmptyString?.uppercased() ?? "",
                              name: team["name"]?.nonEmptyString ?? "")
        }
    }

    /// States sorted as Linear shows them: by category, then position.
    static func workflowStates(_ json: JSONValue) -> [LinearWorkflowState] {
        let parsed = records(in: json, preferring: ["statuses", "states", "issueStatuses", "nodes", "items", "data"])
            .compactMap { state -> (LinearWorkflowState, Double)? in
                guard let id = state["id"]?.nonEmptyString, let name = state["name"]?.nonEmptyString else { return nil }
                let position = state["position"].flatMap { if case .number(let n) = $0 { n } else { nil } } ?? 0
                return (LinearWorkflowState(id: id, name: name, type: LinearStateType(raw: state["type"]?.stringValue)),
                        position)
            }
        let order = LinearStateType.allCases
        return parsed.enumerated().sorted { a, b in
            let (sa, pa) = a.element, (sb, pb) = b.element
            let ta = order.firstIndex(of: sa.type)!, tb = order.firstIndex(of: sb.type)!
            return (ta, pa, a.offset) < (tb, pb, b.offset)
        }.map(\.element.0)
    }

    static func user(_ json: JSONValue) -> LinearUser? {
        let object = json["user"] ?? json["viewer"] ?? json
        guard let id = object["id"]?.nonEmptyString else { return nil }
        let name = object["name"]?.nonEmptyString ?? object["displayName"]?.nonEmptyString
            ?? object["email"]?.nonEmptyString ?? id
        return LinearUser(id: id, name: name, email: object["email"]?.nonEmptyString)
    }

    // MARK: - Fields

    private static func issueState(_ json: JSONValue) -> LinearWorkflowState? {
        let raw = json["state"] ?? json["status"]
        let id = raw?["id"]?.nonEmptyString ?? json["stateId"]?.nonEmptyString ?? json["statusId"]?.nonEmptyString
        let type = raw?["type"]?.stringValue ?? json["stateType"]?.stringValue ?? json["statusType"]?.stringValue
        guard let name = name(of: raw) else { return nil }
        return LinearWorkflowState(id: id, name: name, type: LinearStateType(raw: type))
    }

    private static func teamRef(_ json: JSONValue, key: String) -> LinearTeamRef {
        let team = json["team"]
        return LinearTeamRef(id: team?["id"]?.nonEmptyString ?? json["teamId"]?.nonEmptyString,
                             key: team?["key"]?.nonEmptyString?.uppercased() ?? key,
                             name: name(of: team) ?? json["teamName"]?.nonEmptyString)
    }

    private static func assignee(_ json: JSONValue) -> LinearUser? {
        let raw = json["assignee"]
        guard let name = name(of: raw) ?? raw?["displayName"]?.nonEmptyString else { return nil }
        let id = raw?["id"]?.nonEmptyString ?? json["assigneeId"]?.nonEmptyString ?? ""
        return LinearUser(id: id, name: name, email: raw?["email"]?.nonEmptyString)
    }

    /// A related object's name, whether given as a string or an object.
    private static func name(of value: JSONValue?) -> String? {
        guard let value else { return nil }
        if case .string = value { return value.nonEmptyString }
        return value["name"]?.nonEmptyString
    }

    /// The list of objects in a tool result: the value itself if it is an
    /// array, otherwise the first array found under a preferred key
    /// (searched a few levels deep, e.g. `{"data":{"issues":{"nodes":[…]}}}`).
    static func records(in json: JSONValue, preferring keys: [String], depth: Int = 3) -> [JSONValue] {
        if let array = json.arrayValue { return array }
        guard depth > 0, let object = json.objectValue else { return [] }
        for key in keys {
            if let value = object[key] {
                let found = records(in: value, preferring: keys, depth: depth - 1)
                if !found.isEmpty { return found }
            }
        }
        return []
    }
}
