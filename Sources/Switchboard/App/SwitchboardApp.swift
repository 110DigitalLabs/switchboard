import SwiftUI

@main
struct SwitchboardApp: App {
    @State private var settings: AppSettings
    @State private var store: SessionStore
    @State private var linear: LinearAccount
    private let hookServices: HookServices
    private let navigator: KeyboardNavigator

    init() {
        let settings = AppSettings()
        let hookServices = HookServices()
        // Unit tests run inside the app and must not touch the saved rows.
        let file = HookServices.isRunningTests ? nil : try? SessionFile.standard()
        let store = SessionStore(settings: settings, hooks: hookServices.installation, file: file)
        hookServices.connect(to: store)
        store.restore()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.saveNow() }
        }
        // Tests must not read the real Keychain or reach Linear.
        let linear = LinearAccount(connector: HookServices.isRunningTests
                                       ? FakeLinearConnector() as LinearConnecting
                                       : LinearConnection(),
                                   monitorNetwork: !HookServices.isRunningTests)
        Task { await linear.start() }
        let navigator = KeyboardNavigator(store: store)
        navigator.install()
        self.navigator = navigator
        self.hookServices = hookServices
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _linear = State(initialValue: linear)
    }

    var body: some Scene {
        Window("Switchboard", id: "main") {
            ContentView()
                .environment(store)
                .environment(settings)
                .environment(linear)
                .background(WindowZoomer { [navigator] in navigator.window = $0 })
        }
        .commands { SessionCommands(store: store) }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(linear)
        }
    }
}
