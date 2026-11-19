import AppKit
import Observation

/// Checks GitHub for a newer release at launch and daily, and drives the
/// sidebar's update banner: install, then restart when the user is ready.
@MainActor
@Observable
final class AppUpdater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        /// On disk; running sessions keep going until the user restarts.
        case installed(Release)
        case failed(Release, String)
    }

    private(set) var state: State = .idle

    /// The release the banner is about, if any.
    var bannerRelease: Release? {
        switch state {
        case .available(let release):
            release.version == skippedVersion ? nil : release
        case .installing(let release), .installed(let release), .failed(let release, _):
            release
        case .idle, .checking, .upToDate:
            nil
        }
    }

    typealias Fetch = @Sendable () async throws -> Release
    typealias Install = @Sendable (Release) async throws -> Void

    let currentVersion: AppVersion?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let installRelease: Install
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var schedule: Task<Void, Never>?

    private static let skippedKey = "skippedUpdateVersion"
    private var skippedVersion: AppVersion? {
        didSet { defaults.set(skippedVersion?.description, forKey: Self.skippedKey) }
    }

    init(currentVersion: AppVersion? = .running,
         defaults: UserDefaults = .standard,
         fetch: @escaping Fetch = { try await Release.fetchLatest() },
         install: @escaping Install = { try await UpdateInstaller.install($0) }) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetch = fetch
        self.installRelease = install
        skippedVersion = defaults.string(forKey: Self.skippedKey).flatMap(AppVersion.init)
    }

    /// Checks now and then once a day.
    func start(every interval: Duration = .seconds(24 * 60 * 60)) {
        schedule?.cancel()
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Silent unless an update turns up. Leaves an install in progress alone.
    func check() async {
        switch state {
        case .checking, .installing, .installed: return
        default: break
        }
        let previous = state
        state = .checking
        guard let release = try? await fetch(), let current = currentVersion else {
            state = previous == .checking ? .idle : previous
            return
        }
        state = current < release.version ? .available(release) : .upToDate
    }

    /// From the menu: always says what it found, even a skipped version.
    func checkFromMenu() async {
        skippedVersion = nil
        await check()
        let alert = NSAlert()
        switch state {
        case .available(let release):
            alert.messageText = "Switchboard \(release.version) is available"
            alert.informativeText = "You have \(currentVersion?.description ?? "an older version")."
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { install() }
        case .upToDate:
            alert.messageText = "Switchboard is up to date"
            alert.informativeText = "\(currentVersion?.description ?? "This") is the latest version."
            alert.runModal()
        case .installing, .installed, .failed:
            return  // The banner already shows this.
        case .idle, .checking:
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "GitHub didn't answer. Try again later."
            alert.runModal()
        }
    }

    func skip() {
        guard case .available(let release) = state else { return }
        skippedVersion = release.version
    }

    func install() {
        let release: Release
        switch state {
        case .available(let found), .failed(let found, _): release = found
        default: return
        }
        state = .installing(release)
        Task {
            do {
                try await installRelease(release)
                state = .installed(release)
            } catch {
                state = .failed(release, error.localizedDescription)
            }
        }
    }

    /// Quits and opens the app again once this process is gone.
    func restart(appURL: URL = Bundle.main.bundleURL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                                appURL.path]
        do {
            try relauncher.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
