import SwiftUI

@main
struct SwitchboardApp: App {
    @State private var settings: AppSettings
    @State private var store: SessionStore
    @State private var linear: LinearAccount
    @State private var github: GitHubAccount
    @State private var ticketStatus = TicketStatusModel()
    private let hookServices: HookServices
    private let navigator: KeyboardNavigator

    init() {
        let settings = AppSettings()
        let hookServices = HookServices()
        // Unit tests run inside the app and must not touch the saved rows.
        let fakeLinear = DebugLinear.isEnabled && !HookServices.isRunningTests
        let file = HookServices.isRunningTests
            ? nil : try? SessionFile.standard(name: fakeLinear ? "sessions-fake-linear.json" : "sessions.json")
        let store = SessionStore(settings: settings, hooks: hookServices.installation, file: file)
        hookServices.connect(to: store)
        store.restore()
        // Kept temp rows past Settings' N days: at launch, then every 6 hours.
        if !HookServices.isRunningTests { store.startTempCleanup() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.saveNow() }
        }
        // Tests must not read the real Keychain or reach Linear.
        let connector: LinearConnecting = if fakeLinear {
            FakeLinearConnector(service: FakeLinearService.seeded(), signedIn: true)
        } else if HookServices.isRunningTests {
            FakeLinearConnector()
        } else {
            LinearConnection()
        }
        let linear = LinearAccount(connector: connector,
                                   monitorNetwork: !HookServices.isRunningTests && !fakeLinear)
        store.ticketSource = linear
        Task { await linear.start() }
        let github = GitHubAccount(service: GHCLIService())
        github.store = store
        store.onPullRequestSourcesChanged = { [weak github] in github?.requestRefresh() }
        // Tests must not run gh.
        if !HookServices.isRunningTests { github.start() }
        let navigator = KeyboardNavigator(store: store)
        navigator.install()
        self.navigator = navigator
        self.hookServices = hookServices
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _linear = State(initialValue: linear)
        _github = State(initialValue: github)
    }

    var body: some Scene {
        Window("Switchboard", id: "main") {
            ContentView()
                .environment(store)
                .environment(settings)
                .environment(linear)
                .environment(github)
                .environment(ticketStatus)
                .background(WindowZoomer(sidebarFraction: settings.sidebarWidth.fraction) { [navigator] in
                    navigator.window = $0
                })
                .onChange(of: settings.terminalAppearance) { store.applyTerminalAppearance() }
                .onChange(of: settings.importedThemes) { store.applyTerminalAppearance() }
                .onChange(of: settings.sidebarWidth) { _, width in
                    if let window = navigator.window {
                        WindowZoomer.placeDivider(in: window, fraction: width.fraction)
                    }
                }
        }
        .commands { SessionCommands(store: store) }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(linear)
                .environment(github)
                .environment(store)
        }
    }
}
