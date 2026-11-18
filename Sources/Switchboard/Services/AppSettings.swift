import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let defaultAgent = "defaultAgent"
        static let homeFolder = "homeFolderPath"
        static let tempCleanupDays = "tempCleanupDays"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var defaultAgent: Agent {
        didSet { defaults.set(defaultAgent.rawValue, forKey: Key.defaultAgent) }
    }

    var homeFolderPath: String {
        didSet { defaults.set(homeFolderPath, forKey: Key.homeFolder) }
    }

    /// Used by temp-folder cleanup in a later stage.
    var tempCleanupDays: Int {
        didSet { defaults.set(tempCleanupDays, forKey: Key.tempCleanupDays) }
    }

    var homeFolder: URL { URL(fileURLWithPath: homeFolderPath, isDirectory: true) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultAgent = defaults.string(forKey: Key.defaultAgent).flatMap(Agent.init(rawValue:)) ?? .claudeCode
        homeFolderPath = defaults.string(forKey: Key.homeFolder) ?? Self.defaultHomeFolder()
        let days = defaults.integer(forKey: Key.tempCleanupDays)
        tempCleanupDays = days > 0 ? days : 30
    }

    static func defaultHomeFolder() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent("Projects")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: projects.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return projects.path
        }
        return home.path
    }
}
