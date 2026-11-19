import SwiftUI

struct SessionCommands: Commands {
    let store: SessionStore
    let voice: VoiceController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { store.newSession() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Session In…") { store.isPickerPresented = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Terminal in This Folder") { store.newTerminalInActiveFolder() }
                .keyboardShortcut("n", modifiers: [.command, .control])
        }
        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { resize(by: 1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { resize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Text Size") { store.settings.terminalAppearance.fontSize = TerminalAppearance.defaultFontSize }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            // The shortcut itself is caught by KeyboardNavigator before the
            // terminal sees it; this item makes it discoverable.
            Button("Speak to Session") { voice.toggle() }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
            Divider()
        }
    }

    private func resize(by step: Double) {
        store.settings.terminalAppearance = store.settings.terminalAppearance.resized(by: step)
    }
}
