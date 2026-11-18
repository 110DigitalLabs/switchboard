import SwiftUI

@main
struct SwitchboardApp: App {
    @State private var settings: AppSettings
    @State private var store: SessionStore
    private let hookServices: HookServices

    init() {
        let settings = AppSettings()
        let hookServices = HookServices()
        let store = SessionStore(settings: settings, hooks: hookServices.installation)
        hookServices.connect(to: store)
        self.hookServices = hookServices
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
    }

    var body: some Scene {
        Window("Switchboard", id: "main") {
            ContentView()
                .environment(store)
                .environment(settings)
                .background(WindowZoomer())
        }
        .commands { SessionCommands(store: store) }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
