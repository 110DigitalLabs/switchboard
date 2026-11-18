import AppKit
import Observation

/// Owns the session rows and their live terminals.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    var selectedID: UUID? {
        didSet { if let selectedID { markViewed(selectedID) } }
    }
    var isPickerPresented = false
    var errorMessage: String?

    private(set) var repos: [Repo] = []
    private(set) var isScanningRepos = false

    let settings: AppSettings
    @ObservationIgnored let terminals: TerminalRegistry
    @ObservationIgnored var notifier: Notifier?
    /// Whether the app is frontmost; injectable for tests.
    @ObservationIgnored var isAppActive: () -> Bool = { NSApp?.isActive ?? false }

    init(settings: AppSettings, hooks: HookInstallation? = nil) {
        self.settings = settings
        terminals = TerminalRegistry(hooks: hooks)
    }

    var mainSessions: [Session] { sessions.filter { !$0.kind.isBottomGrouped } }
    var scratchSessions: [Session] { sessions.filter { $0.kind == .scratch } }

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
    func add(_ session: Session, startTerminal: Bool = true) {
        sessions.append(session)
        guard startTerminal else { return }
        let terminal = terminals.makeTerminal(for: session)
        terminal.onExit = { [weak self] _ in self?.setState(.exited, for: session.id) }
        terminal.start()
        selectedID = session.id
    }

    // MARK: Row actions

    func restartShell(_ id: UUID) {
        guard let terminal = terminals.terminal(for: id), !terminal.isRunning else { return }
        setState(.idle, for: id)
        terminal.start()
        selectedID = id
    }

    func close(_ id: UUID) {
        terminals.remove(id)
        sessions.removeAll { $0.id == id }
        if selectedID == id { selectedID = sessions.last?.id }
    }

    private func setState(_ state: WorkingState, for id: UUID) {
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
