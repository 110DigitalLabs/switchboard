import Foundation

/// Writes the hook helper and per-agent settings into
/// `~/Library/Application Support/Switchboard/` at every launch, so an updated
/// app always refreshes them.
enum HookInstaller {
    static func install(fileManager: FileManager = .default) throws -> HookInstallation {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            .appendingPathComponent("Switchboard", isDirectory: true)
        return try install(into: support, home: fileManager.homeDirectoryForCurrentUser,
                           environment: ProcessInfo.processInfo.environment, fileManager: fileManager)
    }

    static func install(into directory: URL, home: URL, environment: [String: String],
                        fileManager: FileManager = .default) throws -> HookInstallation {
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)

        let helper = bin.appendingPathComponent("switchboard-hook")
        try write(Data(HookScript.contents.utf8), to: helper)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let claudeConfig = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let claude = directory.appendingPathComponent("claude-settings.json")
        try writeJSON(ClaudeHookConfig.settings(
            helperPath: helper.path,
            userStatusLine: ClaudeHookConfig.userStatusLine(configDirectory: claudeConfig)
        ), to: claude)

        let gemini = directory.appendingPathComponent("gemini-system-defaults.json")
        try writeJSON(GeminiHookConfig.settings(helperPath: helper.path), to: gemini)

        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")

        return HookInstallation(
            helperPath: helper.path,
            socketPath: socketPath(in: directory),
            claudeSettingsPath: claude.path,
            geminiSettingsPath: gemini.path,
            injectCodexNotify: !CodexHookConfig.userHasNotify(codexHome: codexHome),
            injectGeminiDefaults: !fileManager.fileExists(atPath: GeminiHookConfig.systemDefaultsPath)
        )
    }

    /// Unix socket paths are limited to 104 bytes on macOS; fall back to the
    /// per-user temporary directory (mode 0700 under /var/folders, never the
    /// shared /tmp) when the home folder is unusually long.
    static func socketPath(in directory: URL) -> String {
        let preferred = directory.appendingPathComponent("hook.sock").path
        if preferred.utf8.count < 100 { return preferred }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("switchboard-hook.sock").path
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try write(data, to: url)
    }

    /// Skips identical content so a running agent never sees a rewrite.
    private static func write(_ data: Data, to url: URL) throws {
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try data.write(to: url, options: .atomic)
    }
}
