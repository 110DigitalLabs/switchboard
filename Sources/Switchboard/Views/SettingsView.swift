import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Default agent", selection: $settings.defaultAgent) {
                ForEach(Agent.allCases) { Text($0.displayName).tag($0) }
            }

            LabeledContent("Home folder") {
                HStack {
                    Text((settings.homeFolderPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseHomeFolder() }
                }
            }

            Stepper(value: $settings.tempCleanupDays, in: 1...365) {
                Text("Delete kept temp sessions after \(settings.tempCleanupDays) days")
            }

            Section("Accounts") {
                LinearAccountRow()
                LabeledContent("GitHub") {
                    Text("Coming later").foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseHomeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.homeFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.homeFolderPath = url.path
        }
    }
}
