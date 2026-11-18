import Foundation

/// Installs the hook helper, listens for its messages, and wires
/// notifications to the session store. Lives as long as the app.
@MainActor
final class HookServices {
    let installation: HookInstallation?
    private var server: HookSocketServer?
    private var notifier: Notifier?

    /// Unit tests run inside the app; they must not take over the real
    /// socket or rewrite the installed helper.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        guard !Self.isRunningTests else {
            installation = nil
            return
        }
        do {
            installation = try HookInstaller.install()
        } catch {
            NSLog("Switchboard: could not install agent hooks: \(error)")
            installation = nil
        }
    }

    func connect(to store: SessionStore) {
        guard let installation else { return }
        let notifier = Notifier { [weak store] id in store?.selectedID = id }
        notifier.requestAuthorization()
        store.notifier = notifier
        self.notifier = notifier

        let server = HookSocketServer(path: installation.socketPath) { [weak store] data in
            Task { @MainActor in store?.handleHookData(data) }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("Switchboard: could not listen for agent hooks: \(error)")
        }
    }
}
