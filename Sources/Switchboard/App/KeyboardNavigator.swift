import AppKit

/// Handles Cmd-1…9, Cmd-Up/Down and the voice shortcut (Cmd-Shift-Space,
/// which both starts and stops listening) in the main window. A local key-down
/// monitor runs before the event reaches the key window, so the focused
/// terminal view never sees these; every other key passes through untouched.
@MainActor
final class KeyboardNavigator {
    weak var window: NSWindow?
    var voice: VoiceController?
    private weak var store: SessionStore?
    private var monitor: Any?

    init(store: SessionStore) {
        self.store = store
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors are called on the main thread, so the event
            // never actually crosses an isolation boundary.
            nonisolated(unsafe) let mainThreadEvent = event
            let consumed = MainActor.assumeIsolated { self?.handle(mainThreadEvent) == true }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let store, let window, event.window === window, window.attachedSheet == nil else { return false }
        if let voice, handleVoice(event, voice) { return true }
        guard let key = NavigationKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                      modifiers: event.modifierFlags)
        else { return false }
        let selected: UUID?
        switch key {
        case .position(let position): selected = store.selectVisible(position: position)
        case .previous: selected = store.selectAdjacent(-1)
        case .next: selected = store.selectAdjacent(1)
        }
        if selected != nil { focusSelectedTerminal() }
        return true
    }

    private func handleVoice(_ event: NSEvent, _ voice: VoiceController) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function])
        if event.keyCode == Self.spaceKeyCode, modifiers == [.command, .shift] {
            voice.toggle()
            return true
        }
        return false
    }

    private static let spaceKeyCode: UInt16 = 49

    /// The terminal host also focuses a newly swapped-in view; this covers
    /// re-selecting the current row while focus is in the sidebar.
    private func focusSelectedTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.store?.selectedTerminal?.view, let window = view.window else { return }
            window.makeFirstResponder(view)
        }
    }
}
