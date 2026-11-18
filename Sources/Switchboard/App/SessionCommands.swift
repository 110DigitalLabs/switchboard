import SwiftUI

struct SessionCommands: Commands {
    let store: SessionStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { store.newSession() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Session In…") { store.isPickerPresented = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Resume Existing…") { store.isResumePresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}
