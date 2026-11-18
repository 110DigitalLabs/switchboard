import AppKit
import SwiftTerm

/// One session's terminal view and shell process. Lives as long as the row,
/// independent of whether it is on screen.
@MainActor
final class SessionTerminal: NSObject, LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    var onExit: ((Int32?) -> Void)?

    private let rowID: UUID
    private let extraEnvironment: [String: String]
    private var pendingCommand: String?
    private var pendingDraft: String?
    /// Whether the agent's SessionStart hook will say when its input is up.
    private let agentReportsStart: Bool

    init(session: Session, hooks: HookInstallation?) {
        rowID = session.id
        extraEnvironment = hooks?.environment(for: session.agent) ?? [:]
        agentReportsStart = hooks != nil && session.agent.reportsSessionStartReliably
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.processDelegate = self
    }

    var isRunning: Bool { view.process?.running ?? false }

    /// Starts the login shell in the launch directory, then types the agent's
    /// command into it so it lands in shell history and can be re-run.
    func start(_ launch: SessionLaunch) {
        let base = ProcessInfo.processInfo.environment
        let shell = ShellEnvironment.loginShell(from: base)
        let env = ShellEnvironment.variables(base: base, rowID: rowID, extra: extraEnvironment)
        pendingCommand = launch.command
        pendingDraft = launch.draft

        view.setProcessOutputHandler { [weak self] in
            Task { @MainActor in self?.shellProducedOutput() }
        }
        view.startProcess(
            executable: shell,
            args: [],
            environment: ShellEnvironment.pairs(env),
            execName: ShellEnvironment.loginExecName(for: shell),
            currentDirectory: launch.directory
        )
        // Shells with silent startup files print nothing before the prompt.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.typePendingCommand()
        }
    }

    /// Hangs up the shell the way closing a terminal window does; interactive
    /// shells ignore SIGTERM.
    func terminate() {
        pendingCommand = nil
        pendingDraft = nil
        guard isRunning, let pid = view.process?.shellPid, pid > 0 else { return }
        kill(pid, SIGHUP)
    }

    private func shellProducedOutput() {
        view.setProcessOutputHandler(nil)
        // Give the line editor a moment to take over the TTY after the prompt.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.typePendingCommand()
        }
    }

    private func typePendingCommand() {
        guard let command = pendingCommand, isRunning else { return }
        pendingCommand = nil
        view.send(txt: command + "\r")
        // Agents without reliable hooks never report that they started; for
        // the rest, a timer could type into a startup dialog instead.
        guard pendingDraft != nil, !agentReportsStart else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.typeDraft()
        }
    }

    /// The agent reported its session start: its input box is up, so the
    /// draft prompt can be typed. Return is not pressed.
    func agentDidStart() {
        guard pendingDraft != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.typeDraft()
        }
    }

    private func typeDraft() {
        guard let draft = pendingDraft, pendingCommand == nil, isRunning else { return }
        pendingDraft = nil
        view.send(txt: draft)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        pendingCommand = nil
        pendingDraft = nil
        let status = exitCode.map { "exit code \($0)" } ?? "signal"
        view.feed(text: "\r\n[Shell exited (\(status)). Right-click the session to restart it.]\r\n")
        onExit?(exitCode)
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        pendingCommand = nil
        pendingDraft = nil
        onExit?(nil)
    }
}
