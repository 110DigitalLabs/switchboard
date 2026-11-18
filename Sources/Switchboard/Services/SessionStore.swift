import AppKit
import Observation

/// Owns the session rows and their live terminals.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = [] {
        didSet { scheduleSave() }
    }
    var selectedID: UUID? {
        didSet {
            if let selectedID { markViewed(selectedID) }
            scheduleSave()
        }
    }
    /// Collapse keys of section and ticket groups (see `SessionListLayout`).
    var collapsedGroups: Set<String> = [] {
        didSet { scheduleSave() }
    }
    var isPickerPresented = false
    var errorMessage: String?

    /// Row ID → progress text while "Move to worktree" runs (live only).
    var handoverProgress: [UUID: String] = [:]
    /// The row whose "Move to worktree…" sheet is open.
    var handoverRequestID: UUID?

    private(set) var repos: [Repo] = []
    private(set) var isScanningRepos = false

    let settings: AppSettings
    @ObservationIgnored let terminals: TerminalRegistry
    @ObservationIgnored var notifier: Notifier?
    /// Whether the app is frontmost; injectable for tests.
    @ObservationIgnored var isAppActive: () -> Bool = { NSApp?.isActive ?? false }
    @ObservationIgnored let file: SessionFile?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var lastSaved: Data?
    /// Linear, for tagging sessions with tickets mentioned in prompts.
    @ObservationIgnored weak var ticketSource: TicketSource?
    /// Runs a summary shell line in a directory; injectable for tests.
    @ObservationIgnored var runSummary: (_ line: String, _ directory: String) async throws -> String = {
        try await SummaryProcess.run(line: $0, directory: $1)
    }
    @ObservationIgnored var handoverDirectory = HandoverCommand.defaultDirectory()

    init(settings: AppSettings, hooks: HookInstallation? = nil, file: SessionFile? = nil) {
        self.settings = settings
        self.file = file
        terminals = TerminalRegistry(hooks: hooks)
    }

    var layout: SessionListLayout {
        SessionOrdering.layout(sessions: sessions, sort: settings.sessionSort,
                               grouping: settings.sessionGrouping, collapsed: collapsedGroups)
    }

    var selectedTerminal: SessionTerminal? {
        selectedID.flatMap { terminals.terminal(for: $0) }
    }

    // MARK: Creating

    func create(_ target: NewSessionTarget, agent: Agent) {
        do {
            let session: Session
            switch target {
            case .repo(let repo):
                session = Session(kind: NewSessionTarget.kind(forFolder: repo.url, agent: agent),
                                  folderPath: repo.url.path, agent: agent)
            case .folder(let url):
                session = Session(kind: NewSessionTarget.kind(forFolder: url, agent: agent),
                                  folderPath: url.path, agent: agent)
            case .scratch:
                let folder = try ScratchFolder.create(in: settings.homeFolder)
                session = Session(kind: .scratch, folderPath: folder.path, agent: agent)
            }
            add(session)
        } catch {
            errorMessage = "Could not create the session folder: \(error.localizedDescription)"
        }
    }

    /// Visible for tests; normal creation goes through `create`.
    func add(_ session: Session, startTerminal: Bool = true,
             options: AgentLaunchOptions = AgentLaunchOptions(), draft: String? = nil) {
        sessions.append(session)
        guard startTerminal else { return }
        openTerminal(for: session, launch: .fresh(session, hooks: terminals.hooks, options: options, draft: draft))
        selectedID = session.id
    }

    func openTerminal(for session: Session, launch: SessionLaunch) {
        let terminal = terminals.makeTerminal(for: session)
        terminal.onExit = { [weak self] _ in self?.setState(.exited, for: session.id) }
        terminal.start(launch)
    }

    // MARK: Restoring

    /// Loads the saved rows and reopens each one's terminal, resuming its
    /// agent conversation where possible.
    func restore() {
        guard let file else { return }
        let state = file.load()
        collapsedGroups = state.collapsedGroups
        sessions = state.sessions
        for session in state.sessions {
            let launch = SessionLaunch.reopen(session, hooks: terminals.hooks)
            NSLog("Switchboard: restoring row \(session.id) (\(session.agent.rawValue)) in \(launch.directory): \(launch.command ?? "shell only")")
            openTerminal(for: session, launch: launch)
        }
        selectedID = state.selectedID ?? layout.visibleOrder.first
        NSLog("Switchboard: restored \(state.sessions.count) session(s) from \(file.url.path)")
    }

    // MARK: Row actions

    /// Reopens an exited row's shell, resuming its conversation when known
    /// rather than starting a new worktree.
    func restartShell(_ id: UUID) {
        guard let terminal = terminals.terminal(for: id), !terminal.isRunning,
              let session = sessions.first(where: { $0.id == id }) else { return }
        setState(.idle, for: id)
        terminal.start(.reopen(session, hooks: terminals.hooks))
        selectedID = id
    }

    func close(_ id: UUID) {
        terminals.remove(id)
        sessions.removeAll { $0.id == id }
        if selectedID == id { selectedID = sessions.last?.id }
    }

    func setState(_ state: WorkingState, for id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].workingState = state
    }

    /// Replaces a row's value; no-op for rows that are gone or unchanged.
    func update(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }),
              sessions[index] != session else { return }
        sessions[index] = session
    }

    /// The user is looking at this row: clear its badge and settle "finished".
    func markViewed(_ id: UUID) {
        notifier?.clear(rowID: id)
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].hasBadge { sessions[index].hasBadge = false }
        if sessions[index].workingState == .finished { sessions[index].activity.markViewed() }
    }

    // MARK: Repos

    func refreshRepos() async {
        guard !isScanningRepos else { return }
        isScanningRepos = true
        let home = settings.homeFolder
        repos = await Task.detached(priority: .userInitiated) { RepoScanner.scan(home: home) }.value
        isScanningRepos = false
    }
}
