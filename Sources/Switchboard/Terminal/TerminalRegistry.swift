import Foundation

/// Keeps every session's terminal alive, keyed by session ID, so changing the
/// selection never recreates or kills a shell.
@MainActor
final class TerminalRegistry {
    private var terminals: [UUID: SessionTerminal] = [:]
    let hooks: HookInstallation?
    private(set) var appearance = TerminalAppearance()
    private(set) var theme = TerminalTheme.system

    init(hooks: HookInstallation?) {
        self.hooks = hooks
    }

    /// Restyles every open terminal and the ones made after.
    func apply(_ appearance: TerminalAppearance, theme: TerminalTheme) {
        self.appearance = appearance
        self.theme = theme
        for terminal in terminals.values { appearance.apply(theme, to: terminal.view) }
    }

    func terminal(for id: UUID) -> SessionTerminal? { terminals[id] }

    func makeTerminal(for session: Session) -> SessionTerminal {
        let terminal = SessionTerminal(session: session, hooks: hooks)
        appearance.apply(theme, to: terminal.view)
        terminals[session.id] = terminal
        return terminal
    }

    func remove(_ id: UUID) {
        guard let terminal = terminals.removeValue(forKey: id) else { return }
        terminal.onExit = nil
        terminal.terminate()
        terminal.view.removeFromSuperview()
    }
}
