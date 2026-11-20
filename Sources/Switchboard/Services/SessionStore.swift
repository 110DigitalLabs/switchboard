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
    /// The temp or scratch row whose "Delete folder?" dialog is open.
    var closeRequestID: UUID?
    /// The row whose "Change Ticket…" dialog is open.
    var ticketEditRequestID: UUID?

    /// Claude Code and Codex conversations running in other terminals,
    /// newest first; refreshed by `startWatchingElsewhere()`.
    var elsewhere: [PastConversation] = []

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
    /// Moves a folder to the Trash; injectable for tests.
    @ObservationIgnored var trashItem: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
    @ObservationIgnored var cleanupTask: Task<Void, Never>?
    @ObservationIgnored var elsewhereTask: Task<Void, Never>?
    /// Called when a row gains a PR or a worktree to look PRs up for.
    @ObservationIgnored var onPullRequestSourcesChanged: (() -> Void)?

    init(settings: AppSettings, hooks: HookInstallation? = nil, file: SessionFile? = nil) {
        self.settings = settings
        self.file = file
        terminals = TerminalRegistry(hooks: hooks)
        applyTerminalAppearance()
    }

    func applyTerminalAppearance() {
        terminals.apply(settings.terminalAppearance, theme: settings.terminalTheme)
    }

    var layout: SessionListLayout { layout(assigned: []) }

    /// The list as shown, with the user's assigned issues in Tickets mode.
    /// Unstarted issues have no sessions, so navigation is the same either way.
    func layout(assigned: [LinearIssue]) -> SessionListLayout {
        SessionOrdering.layout(sessions: sessions, sort: settings.sessionSort, grouping: settings.sessionGrouping,
                               assigned: assigned, collapsed: collapsedGroups)
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
                session = Session(kind: .folder, folderPath: repo.url.path, agent: agent)
            case .folder(let url):
                session = Session(kind: .folder, folderPath: url.path, agent: agent)
            case .scratch:
                let folder = try ScratchFolder.create(in: settings.homeFolder)
                session = Session(kind: .scratch, folderPath: folder.path, agent: agent)
            }
            add(session)
        } catch {
            errorMessage = "Could not create the session folder: \(error.localizedDescription)"
        }
    }

    /// "+" and Cmd-N: start right away in the repo dropdown's repo with the
    /// default agent, in the repo folder itself rather than a new worktree,
    /// or open the picker when the dropdown is None or its repo is gone.
    func newSession() {
        if let repo = settings.ticketRepo {
            add(Session(kind: .folder, folderPath: repo.url.path, agent: settings.defaultAgent))
        } else {
            isPickerPresented = true
        }
    }

    /// Cmd-Ctrl-N: a plain terminal in the selected row's folder (its
    /// worktree when the agent made one), under the same ticket. With no
    /// row selected it uses the repo dropdown's repo, then the home folder.
    func newTerminalInActiveFolder() {
        let source = selectedID.flatMap { id in sessions.first { $0.id == id } }
        var session = Session(kind: .folder, folderPath: activeFolder, agent: .terminal)
        session.ticketID = source?.ticketID
        session.ticketTitle = source?.ticketTitle
        session.ticketSetByUser = source?.ticketSetByUser ?? false
        session.linearProjectName = source?.linearProjectName
        add(session)
    }

    /// The selected row's folder, or its worktree when the agent made one.
    var activeFolder: String {
        let source = selectedID.flatMap { id in sessions.first { $0.id == id } }
        return source.map { $0.workingDirectory ?? $0.folderPath }
            ?? settings.ticketRepo?.url.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// A scratch row whose shell runs `command` instead of an agent, e.g.
    /// `gh auth login --web`. The agent can be started there afterwards.
    func startCommandSession(_ command: String, title: String, agent: Agent) {
        do {
            let folder = try ScratchFolder.create(in: settings.homeFolder)
            var session = Session(kind: .scratch, folderPath: folder.path, agent: agent)
            session.agentTitle = title
            sessions.append(session)
            openTerminal(for: session, launch: SessionLaunch(directory: folder.path, command: command))
            selectedID = session.id
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

    /// Loads the saved rows and reopens each live row's terminal, resuming
    /// its agent conversation where possible. Kept rows stay closed.
    func restore() {
        guard let file else { return }
        let state = file.load()
        collapsedGroups = state.collapsedGroups
        sessions = state.sessions
        for session in state.sessions where !session.isKept {
            let launch = SessionLaunch.reopen(session, hooks: terminals.hooks)
            NSLog("Switchboard: restoring row \(session.id) (\(session.agent.rawValue)) in \(launch.directory): \(launch.command ?? "shell only")")
            openTerminal(for: session, launch: launch)
        }
        let live = Set(state.sessions.filter { !$0.isKept }.map(\.id))
        selectedID = state.selectedID.flatMap { live.contains($0) ? $0 : nil } ?? layout.visibleOrder.first
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
        if selectedID == id { selectedID = sessions.last(where: { !$0.isKept })?.id }
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
