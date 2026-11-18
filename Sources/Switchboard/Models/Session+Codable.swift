import Foundation

/// Persisted form of a row. Live state (activity, badge, status line) is not
/// saved: it is stale after a relaunch and the agent reports it again.
/// Decoding is tolerant: only identity, kind, folder and agent are required,
/// and unknown keys are ignored.
extension Session: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, folderPath, agent, createdAt
        case agentConversationID, workingDirectory, agentTitle, ticketID
        case linearProjectName, prURLs, agentModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            kind: try c.decode(SessionKind.self, forKey: .kind),
            folderPath: try c.decode(String.self, forKey: .folderPath),
            agent: try c.decode(Agent.self, forKey: .agent),
            createdAt: (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        )
        agentConversationID = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .agentConversationID))
        workingDirectory = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .workingDirectory))
        agentTitle = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .agentTitle))
        ticketID = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .ticketID))
        linearProjectName = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .linearProjectName))
        prURLs = (try? c.decodeIfPresent([String].self, forKey: .prURLs)) ?? []
        agentModel = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .agentModel))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(folderPath, forKey: .folderPath)
        try c.encode(agent, forKey: .agent)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(agentConversationID, forKey: .agentConversationID)
        try c.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try c.encodeIfPresent(agentTitle, forKey: .agentTitle)
        try c.encodeIfPresent(ticketID, forKey: .ticketID)
        try c.encodeIfPresent(linearProjectName, forKey: .linearProjectName)
        if !prURLs.isEmpty { try c.encode(prURLs, forKey: .prURLs) }
        try c.encodeIfPresent(agentModel, forKey: .agentModel)
    }

    private static func nonEmpty(_ value: String??) -> String? {
        guard let value = value ?? nil, !value.isEmpty else { return nil }
        return value
    }
}
