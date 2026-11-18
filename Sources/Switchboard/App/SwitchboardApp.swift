import SwiftUI

@main
struct SwitchboardApp: App {
    @State private var settings: AppSettings
    @State private var store: SessionStore

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: SessionStore(settings: settings))
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
