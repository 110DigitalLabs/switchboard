import Foundation

/// Everything restored on relaunch: rows, collapsed groups, the selection.
struct PersistedState: Codable, Equatable, Sendable {
    var sessions: [Session] = []
    var collapsedGroups: Set<String> = []
    var selectedID: UUID?

    init(sessions: [Session] = [], collapsedGroups: Set<String> = [], selectedID: UUID? = nil) {
        self.sessions = sessions
        self.collapsedGroups = collapsedGroups
        self.selectedID = selectedID
    }

    private enum CodingKeys: String, CodingKey {
        case version, sessions, collapsedGroups, selectedID
    }

    /// Requires a JSON object; anything inside it that does not decode (a bad
    /// row, a wrong type) is dropped rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rows = (try? c.decodeIfPresent([Lossy<Session>].self, forKey: .sessions)) ?? []
        var seen = Set<UUID>()
        sessions = rows.compactMap(\.value).filter { seen.insert($0.id).inserted }
        collapsedGroups = Set((try? c.decodeIfPresent([Lossy<String>].self, forKey: .collapsedGroups))?
            .compactMap(\.value) ?? [])
        selectedID = (try? c.decodeIfPresent(UUID.self, forKey: .selectedID)) ?? nil
        if let selectedID, !seen.contains(selectedID) { self.selectedID = nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(collapsedGroups.sorted(), forKey: .collapsedGroups)
        try c.encodeIfPresent(selectedID, forKey: .selectedID)
    }

    static func decode(_ data: Data) throws -> PersistedState {
        try decoder.decode(PersistedState.self, from: data)
    }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

/// Decodes a value or nothing, so one bad array element is skipped.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
