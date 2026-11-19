import AppKit

/// Turns finished utterances into actions on the session list: dictation is
/// typed into the selected session's terminal (Return is never pressed except
/// by saying "send"), and "Switchboard N" selects the Nth visible row.
@MainActor
final class VoiceController {
    let input = VoiceInput()
    private weak var store: SessionStore?

    init(store: SessionStore) {
        self.store = store
        input.onTranscript = { [weak self] transcript in
            guard let command = VoiceCommand(transcript: transcript) else { return }
            self?.perform(command)
        }
    }

    func toggle() { input.toggle() }

    func cancel() { input.cancel() }

    func perform(_ command: VoiceCommand) {
        guard let store else { return }
        switch command {
        case .select(let position, let then):
            guard store.selectVisible(position: position) != nil else {
                NSSound.beep()
                return
            }
            focusSelectedTerminal()
            if let then { type(then) }
        case .submit:
            store.selectedTerminal?.view.send(txt: "\r")
        case .dictate(let text):
            type(text)
        }
    }

    /// Sanitized like any other outside text, so a transcript can never
    /// carry a line break that submits on its own. The trailing space keeps
    /// consecutive utterances apart.
    private func type(_ text: String) {
        guard let terminal = store?.selectedTerminal else {
            NSSound.beep()
            return
        }
        let clean = TypedText.sanitize(text).trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        terminal.view.send(txt: clean + " ")
    }

    private func focusSelectedTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.store?.selectedTerminal?.view, let window = view.window else { return }
            window.makeFirstResponder(view)
        }
    }
}
