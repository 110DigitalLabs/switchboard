import Foundation

/// Puts a newer Switchboard.app in place of the running one. The running app
/// keeps going; the new version starts on the next launch.
enum UpdateInstaller {
    enum Method: Equatable {
        /// Installed by the Homebrew cask: let brew upgrade it, so brew's
        /// record of the installed version stays right.
        case homebrew(brew: String)
        /// Download the release zip and swap the bundle.
        case direct
    }

    static let caskrooms = ["/opt/homebrew/Caskroom/switchboard", "/usr/local/Caskroom/switchboard"]
    static let brews = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// Where the cask puts the app; brew only upgrades that copy.
    static let caskAppPaths = ["/Applications/Switchboard.app",
                               NSHomeDirectory() + "/Applications/Switchboard.app"]

    static func method(appURL: URL, fileManager: FileManager = .default) -> Method {
        guard caskAppPaths.contains(appURL.resolvingSymlinksInPath().path) else { return .direct }
        for (caskroom, brew) in zip(caskrooms, brews)
        where fileManager.fileExists(atPath: caskroom) && fileManager.isExecutableFile(atPath: brew) {
            return .homebrew(brew: brew)
        }
        return .direct
    }

    static func install(_ release: Release, appURL: URL = Bundle.main.bundleURL) async throws {
        switch method(appURL: appURL) {
        case .homebrew(let brew):
            try await upgradeWithHomebrew(brew, to: release, appURL: appURL)
        case .direct:
            try await replaceDirectly(with: release, appURL: appURL)
        }
    }

    // MARK: Homebrew

    private static func upgradeWithHomebrew(_ brew: String, to release: Release, appURL: URL) async throws {
        var environment = ProcessInfo.processInfo.environment
        let brewBin = (brew as NSString).deletingLastPathComponent
        environment["PATH"] = [brewBin, "/usr/bin", "/bin", "/usr/sbin", "/sbin", environment["PATH"]]
            .compactMap { $0 }.joined(separator: ":")
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        let output: ProcessRunner.Output
        do {
            output = try await ProcessRunner.run(brew, ["upgrade", "--cask", "switchboard"],
                                                 environment: environment, timeout: .seconds(15 * 60))
        } catch {
            throw UpdateError("Homebrew didn't finish the upgrade (\(error)).")
        }
        if let installed = AppVersion.installed(at: appURL), installed >= release.version { return }
        guard output.status == 0 else {
            throw UpdateError("brew upgrade failed: \(lastLine(of: output.stderr))")
        }
        throw UpdateError("Homebrew doesn't have Switchboard \(release.version) yet. Try again later.")
    }

    // MARK: Direct

    private static func replaceDirectly(with release: Release, appURL: URL) async throws {
        guard let zipURL = release.zipURL else {
            throw UpdateError("Release \(release.version) has no app to download.")
        }
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw UpdateError("Switchboard can't write to \(appURL.deletingLastPathComponent().path).")
        }
        guard let currentTeam = await teamIdentifier(of: appURL) else {
            throw UpdateError("This build isn't Developer ID signed, so it can't update itself.")
        }

        let work = fileManager.temporaryDirectory.appendingPathComponent("SwitchboardUpdate-\(UUID().uuidString)")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("Downloading Switchboard \(release.version) failed.")
        }
        let zip = work.appendingPathComponent("Switchboard.zip")
        try fileManager.moveItem(at: downloaded, to: zip)

        let unpacked = work.appendingPathComponent("unpacked")
        let unzip = try await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path],
                                                timeout: .seconds(120))
        let newApp = unpacked.appendingPathComponent("Switchboard.app")
        guard unzip.status == 0, fileManager.fileExists(atPath: newApp.path) else {
            throw UpdateError("The downloaded update couldn't be unpacked.")
        }

        // Only accept an app that is intact, notarized, signed by the same
        // team as this one, and actually the version we asked for.
        let verify = try await ProcessRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path],
                                                 timeout: .seconds(120))
        let assess = try await ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path],
                                                 timeout: .seconds(120))
        guard verify.status == 0, assess.status == 0,
              await teamIdentifier(of: newApp) == currentTeam else {
            throw UpdateError("The downloaded update failed its signature check, so it wasn't installed.")
        }
        guard let newVersion = AppVersion.installed(at: newApp), newVersion >= release.version else {
            throw UpdateError("The downloaded app isn't version \(release.version).")
        }

        _ = try fileManager.replaceItemAt(appURL, withItemAt: newApp)
    }

    /// The signing team, or nil for ad-hoc and unsigned builds.
    static func teamIdentifier(of appURL: URL) async -> String? {
        guard let output = try? await ProcessRunner.run("/usr/bin/codesign", ["-dv", appURL.path],
                                                         timeout: .seconds(30)) else { return nil }
        return teamIdentifier(inCodesignOutput: output.stderr)
    }

    static func teamIdentifier(inCodesignOutput text: String) -> String? {
        let line = text.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
        guard let value = line?.dropFirst("TeamIdentifier=".count), !value.isEmpty, value != "not set" else {
            return nil
        }
        return String(value)
    }

    private static func lastLine(of text: String) -> String {
        text.split(separator: "\n").last.map(String.init) ?? "unknown error"
    }
}
