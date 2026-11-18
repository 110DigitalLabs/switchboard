import Foundation
import Network
import Observation

/// The app's Linear connection: sign-in state, the signed-in service, and
/// the assigned-issue list, polled about once a minute while signed in.
@MainActor
@Observable
final class LinearAccount {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn(userName: String)
        case offline
        case error(String)
    }

    private(set) var status: Status = .signedOut
    /// Open issues assigned to the user, newest poll.
    private(set) var assignedIssues: [LinearIssue] = []
    /// Upper-cased team keys, for `TicketMentions.find(in:validTeamKeys:)`.
    private(set) var teamKeys: Set<String> = []
    private(set) var lastRefreshed: Date?
    /// The last polling error while still signed in; cleared on success.
    private(set) var pollError: String?
    /// Kept while offline so the UI can still say who is signed in.
    private(set) var userName: String?
    /// Present whenever credentials exist (signed in or offline).
    private(set) var service: LinearService?

    /// Ticket features are usable.
    var isConnected: Bool {
        if case .signedIn = status { return true }
        return false
    }

    let pollInterval: Duration
    let maxBackoff: Duration
    private let connector: LinearConnecting
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    init(connector: LinearConnecting, pollInterval: Duration = .seconds(60),
         maxBackoff: Duration = .seconds(600), monitorNetwork: Bool = true) {
        self.connector = connector
        self.pollInterval = pollInterval
        self.maxBackoff = maxBackoff
        if monitorNetwork { startPathMonitor() }
    }

    /// Restores stored credentials and loads the first data.
    func start() async {
        guard service == nil, let restored = await connector.restore() else { return }
        await connect(restored)
    }

    func signIn() async {
        guard status != .signingIn else { return }
        status = .signingIn
        do {
            await connect(try await connector.signIn())
        } catch OAuthError.cancelled {
            status = .signedOut
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func cancelSignIn() {
        connector.cancelSignIn()
    }

    func signOut() async {
        stopPolling()
        await connector.signOut()
        clear()
        status = .signedOut
    }

    /// Fetches assigned issues now, outside the poll schedule.
    func refreshNow() async {
        guard service != nil else { return }
        await poll()
        schedulePolling()
    }

    // MARK: - Connection

    private func connect(_ service: LinearService) async {
        self.service = service
        do {
            let user = try await service.currentUser()
            userName = user.name
            status = .signedIn(userName: user.name)
            teamKeys = (try? await service.teamKeys()) ?? []
            await poll()
            schedulePolling()
        } catch {
            handle(LinearError(error), duringPoll: false)
            // Retries with backoff when the failure left the service in place.
            schedulePolling()
        }
    }

    private func poll() async {
        guard let service else { return }
        do {
            let issues = try await service.myAssignedIssues()
            assignedIssues = issues
            lastRefreshed = Date()
            pollError = nil
            consecutiveFailures = 0
            if !isConnected {
                guard let userName else {
                    // Recovered from offline before the user was ever loaded.
                    await connect(service)
                    return
                }
                status = .signedIn(userName: userName)
            }
            if teamKeys.isEmpty { teamKeys = (try? await service.teamKeys()) ?? [] }
        } catch {
            handle(LinearError(error), duringPoll: true)
        }
    }

    private func handle(_ error: LinearError, duringPoll: Bool) {
        switch error {
        case .signedOut:
            stopPolling()
            clear()
            status = .signedOut
            Task { await connector.signOut() }
        case .offline:
            stopPolling()
            status = .offline
        default:
            consecutiveFailures += 1
            if duringPoll, isConnected {
                pollError = error.localizedDescription
            } else {
                status = .error(error.localizedDescription)
            }
        }
    }

    private func clear() {
        service = nil
        assignedIssues = []
        teamKeys = []
        userName = nil
        pollError = nil
        lastRefreshed = nil
        consecutiveFailures = 0
    }

    // MARK: - Polling

    /// The wait before the next poll: the interval, doubled per
    /// consecutive failure, capped at `max`.
    nonisolated static func backoffDelay(failures: Int, interval: Duration, max: Duration) -> Duration {
        guard failures > 0 else { return interval }
        let factor = 1 << Swift.min(failures, 16)
        return Swift.min(interval * factor, max)
    }

    private func schedulePolling() {
        pollTask?.cancel()
        guard service != nil, status != .offline else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = Self.backoffDelay(failures: consecutiveFailures, interval: pollInterval, max: maxBackoff)
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, service != nil, status != .offline else { return }
                if case .error = status, consecutiveFailures > 0 {
                    // Retry the whole connection after a failed connect.
                    if let service { await connect(service) }
                    return
                }
                await poll()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkBecameAvailable() }
        }
        monitor.start(queue: DispatchQueue(label: "dev.switchboard.linear.network"))
        pathMonitor = monitor
    }

    /// Resumes after an offline pause.
    func networkBecameAvailable() {
        guard status == .offline, service != nil else { return }
        Task { await refreshNow() }
    }
}
