import Foundation
@testable import Switchboard

enum TicketTestSupport {
    static func issue(_ id: String, title: String = "A ticket", description: String? = "Body text",
                      project: String? = "Switchboard", assignee: LinearUser? = nil) -> LinearIssue {
        LinearIssue(id: "id-\(id)", identifier: id, title: title, description: description,
                    url: URL(string: "https://linear.app/acme/issue/\(id)"),
                    state: LinearWorkflowState(id: "s1", name: "Todo", type: .unstarted),
                    team: LinearTeamRef(id: "t1", key: String(id.split(separator: "-")[0]), name: nil),
                    projectName: project, assignee: assignee)
    }

    static func session(_ kind: SessionKind = .folder, path: String = "/tmp/x", ticket: String? = nil,
                        agent: Agent = .claudeCode, created: TimeInterval = 0) -> Session {
        var session = Session(kind: kind, folderPath: path, agent: agent,
                              createdAt: Date(timeIntervalSince1970: created))
        session.ticketID = ticket
        return session
    }

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchboard-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    static func store(home: URL? = nil) -> SessionStore {
        let defaults = UserDefaults(suiteName: "TicketTests-\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        if let home { settings.homeFolderPath = home.path }
        return SessionStore(settings: settings)
    }
}

/// A connected Linear stand-in for the session store.
@MainActor
final class StubTicketSource: TicketSource {
    var teamKeys: Set<String>
    var isConnected: Bool
    var service: LinearService?

    init(teamKeys: Set<String> = ["ENG"], isConnected: Bool = true, service: LinearService? = nil) {
        self.teamKeys = teamKeys
        self.isConnected = isConnected
        self.service = service
    }
}
