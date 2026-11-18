import SwiftUI

struct SessionCommands: Commands {
    let store: SessionStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session…") { store.isPickerPresented = true }
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}
