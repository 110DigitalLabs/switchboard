import Foundation
import Testing
@testable import Switchboard

struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() {
        #expect(AppVersion("v0.1.2")?.components == [0, 1, 2])
        #expect(AppVersion("0.1.2")?.components == [0, 1, 2])
        #expect(AppVersion(" 1.0\n")?.components == [1, 0])
    }

    @Test(arguments: ["", "v", "1..2", "1.2-beta", "latest", "1.-2"])
    func rejectsNonNumeric(_ text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesNumericallyNotAlphabetically() {
        #expect(AppVersion("0.1.9")! < AppVersion("0.1.10")!)
        #expect(AppVersion("0.2")! > AppVersion("0.1.99")!)
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(!(AppVersion("0.1.2")! < AppVersion("0.1.2")!))
    }
}

struct ReleaseParsingTests {
    private func json(tag: String = "v0.1.3", draft: Bool = false, prerelease: Bool = false,
                      assets: [String] = ["Switchboard-0.1.3.zip"]) -> Data {
        let list = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://example.com/dl/\#($0)"}"#
        }.joined(separator: ",")
        return Data(#"""
        {"tag_name":"\#(tag)","html_url":"https://example.com/releases/\#(tag)",
         "draft":\#(draft),"prerelease":\#(prerelease),"assets":[\#(list)]}
        """#.utf8)
    }

    @Test func readsVersionPageAndZip() throws {
        let release = try #require(Release.parse(gitHubJSON: json()))
        #expect(release.version == AppVersion("0.1.3"))
        #expect(release.pageURL.absoluteString == "https://example.com/releases/v0.1.3")
        #expect(release.zipURL?.absoluteString == "https://example.com/dl/Switchboard-0.1.3.zip")
    }

    @Test func prefersTheZipNamedForTheVersion() throws {
        let release = try #require(Release.parse(gitHubJSON: json(assets: ["Switchboard-dSYM.zip",
                                                                          "Switchboard-0.1.3.zip"])))
        #expect(release.zipURL?.lastPathComponent == "Switchboard-0.1.3.zip")
    }

    @Test func ignoresDraftsAndPrereleases() {
        #expect(Release.parse(gitHubJSON: json(draft: true)) == nil)
        #expect(Release.parse(gitHubJSON: json(prerelease: true)) == nil)
        #expect(Release.parse(gitHubJSON: json(tag: "nightly")) == nil)
    }

    @Test func readsTeamIdentifierFromCodesign() {
        #expect(UpdateInstaller.teamIdentifier(inCodesignOutput: "Identifier=x\nTeamIdentifier=7LMTQRL996\n")
                == "7LMTQRL996")
        #expect(UpdateInstaller.teamIdentifier(inCodesignOutput: "TeamIdentifier=not set\n") == nil)
        #expect(UpdateInstaller.teamIdentifier(inCodesignOutput: "Signature=adhoc\n") == nil)
    }
}

@MainActor
struct AppUpdaterTests {
    private static let newer = Release(version: AppVersion("0.2.0")!,
                                       pageURL: URL(string: "https://example.com/r")!, zipURL: nil)

    private func defaults() -> UserDefaults {
        let name = "AppUpdaterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func updater(current: String = "0.1.2", release: Release = newer,
                         defaults: UserDefaults? = nil,
                         install: @escaping AppUpdater.Install = { _ in }) -> AppUpdater {
        AppUpdater(currentVersion: AppVersion(current), defaults: defaults ?? self.defaults(),
                   fetch: { release }, install: install)
    }

    @Test func offersANewerRelease() async {
        let updater = updater()
        await updater.check()
        #expect(updater.state == .available(Self.newer))
        #expect(updater.bannerRelease == Self.newer)
    }

    @Test func staysQuietWhenCurrent() async {
        let updater = updater(current: "0.2.0")
        await updater.check()
        #expect(updater.state == .upToDate)
        #expect(updater.bannerRelease == nil)
    }

    @Test func staysQuietWhenGitHubFails() async {
        let updater = AppUpdater(currentVersion: AppVersion("0.1.2"), defaults: defaults(),
                                 fetch: { throw UpdateError("offline") }, install: { _ in })
        await updater.check()
        #expect(updater.state == .idle)
        #expect(updater.bannerRelease == nil)
    }

    @Test func skippingHidesTheBannerAcrossLaunches() async {
        let store = defaults()
        let first = updater(defaults: store)
        await first.check()
        first.skip()
        #expect(first.bannerRelease == nil)

        let relaunched = updater(defaults: store)
        await relaunched.check()
        #expect(relaunched.bannerRelease == nil)
    }

    @Test func installsThenWaitsForRestart() async throws {
        let updater = updater()
        await updater.check()
        updater.install()
        #expect(updater.state == .installing(Self.newer))
        try await waitUntil { if case .installed = updater.state { true } else { false } }
        #expect(updater.bannerRelease == Self.newer)
        // A later daily check must not undo the pending restart.
        await updater.check()
        #expect(updater.state == .installed(Self.newer))
    }

    @Test func reportsAFailedInstallAndCanRetry() async throws {
        let attempts = LockedValue(0)
        let updater = updater(install: { _ in
            attempts.set(attempts.get() + 1)
            if attempts.get() == 1 { throw UpdateError("disk full") }
        })
        await updater.check()
        updater.install()
        try await waitUntil { if case .failed = updater.state { true } else { false } }
        #expect(updater.state == .failed(Self.newer, "disk full"))
        updater.install()
        try await waitUntil { if case .installed = updater.state { true } else { false } }
        #expect(attempts.get() == 2)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
