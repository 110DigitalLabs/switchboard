import Foundation

/// Keeps every session's terminal alive, keyed by session ID, so changing the
/// selection never recreates or kills a shell.
@MainActor
final class TerminalRegistry {
    private var terminals: [UUID: SessionTerminal] = [:]
    let hooks: HookInstallation?

    init(hooks: HookInstallation?) {
        self.hooks = hooks
    }

    func terminal(for id: UUID) -> SessionTerminal? { terminals[id] }

    func makeTerminal(for session: Session) -> SessionTerminal {
        let terminal = SessionTerminal(session: session, hooks: hooks)
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
