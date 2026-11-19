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
        static let sessionSort = "sessionSort"
        static let sessionGrouping = "sessionGrouping"
        static let ticketRepo = "ticketRepoPath"
        static let sidebarWidth = "sidebarWidth"
        static let sessionListTextSize = "sessionListTextSize"
        static let terminalAppearance = "terminalAppearance"
        static let importedThemes = "importedTerminalThemes"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var defaultAgent: Agent {
        didSet { defaults.set(defaultAgent.rawValue, forKey: Key.defaultAgent) }
    }

    var homeFolderPath: String {
        didSet { defaults.set(homeFolderPath, forKey: Key.homeFolder) }
    }

    /// Kept temp and scratch rows are deleted this many days after closing.
    var tempCleanupDays: Int {
        didSet { defaults.set(tempCleanupDays, forKey: Key.tempCleanupDays) }
    }

    var sessionSort: SessionSort {
        didSet { defaults.set(sessionSort.rawValue, forKey: Key.sessionSort) }
    }

    var sessionGrouping: SessionGrouping {
        didSet { defaults.set(sessionGrouping.rawValue, forKey: Key.sessionGrouping) }
    }

    /// The search bar's repo dropdown: where ticket sessions start. Nil is
    /// "None" (a temp planning folder under `<home>/tickets`).
    var ticketRepoPath: String? {
        didSet { defaults.set(ticketRepoPath, forKey: Key.ticketRepo) }
    }

    var sidebarWidth: SidebarWidth {
        didSet { defaults.set(sidebarWidth.rawValue, forKey: Key.sidebarWidth) }
    }

    var sessionListTextSize: SessionListTextSize {
        didSet { defaults.set(sessionListTextSize.rawValue, forKey: Key.sessionListTextSize) }
    }

    var terminalAppearance: TerminalAppearance {
        didSet { save(terminalAppearance, forKey: Key.terminalAppearance) }
    }

    /// Themes added from `.itermcolors` files or the iTerm2 profile.
    var importedThemes: [TerminalTheme] {
        didSet { save(importedThemes, forKey: Key.importedThemes) }
    }

    var terminalThemes: [TerminalTheme] { TerminalTheme.builtIn + importedThemes }

    /// The chosen theme; System when it has been removed.
    var terminalTheme: TerminalTheme {
        terminalThemes.first { $0.id == terminalAppearance.themeID } ?? .system
    }

    /// Adds or replaces (by ID) an imported theme and selects it.
    func importTheme(_ theme: TerminalTheme) {
        importedThemes.removeAll { $0.id == theme.id }
        importedThemes.append(theme)
        terminalAppearance.themeID = theme.id
    }

    func removeImportedTheme(_ id: String) {
        importedThemes.removeAll { $0.id == id }
        if terminalAppearance.themeID == id { terminalAppearance.themeID = TerminalTheme.systemID }
    }

    var homeFolder: URL { URL(fileURLWithPath: homeFolderPath, isDirectory: true) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultAgent = defaults.string(forKey: Key.defaultAgent).flatMap(Agent.init(rawValue:)) ?? .claudeCode
        homeFolderPath = defaults.string(forKey: Key.homeFolder) ?? Self.defaultHomeFolder()
        let days = defaults.integer(forKey: Key.tempCleanupDays)
        tempCleanupDays = days > 0 ? days : 30
        sessionSort = defaults.string(forKey: Key.sessionSort).flatMap(SessionSort.init(rawValue:)) ?? .ticket
        sessionGrouping = defaults.string(forKey: Key.sessionGrouping).flatMap(SessionGrouping.init(rawValue:)) ?? .ticket
        ticketRepoPath = defaults.string(forKey: Key.ticketRepo)
        sidebarWidth = defaults.string(forKey: Key.sidebarWidth).flatMap(SidebarWidth.init(rawValue:)) ?? .third
        sessionListTextSize = defaults.string(forKey: Key.sessionListTextSize)
            .flatMap(SessionListTextSize.init(rawValue:)) ?? .small
        terminalAppearance = Self.load(TerminalAppearance.self, from: defaults, key: Key.terminalAppearance)
            ?? TerminalAppearance()
        importedThemes = Self.load([TerminalTheme].self, from: defaults, key: Key.importedThemes) ?? []
    }

    private func save(_ value: some Encodable, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
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
