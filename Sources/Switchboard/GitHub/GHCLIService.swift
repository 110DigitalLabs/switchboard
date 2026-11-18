import Foundation

/// GitHubService backed by the `gh` CLI. gh is found by absolute path
/// (the app's PATH lacks Homebrew), falling back to the login shell's
/// `command -v gh`. Every call has a timeout; output is gh's JSON only.
actor GHCLIService: GitHubService {
    private let timeout: Duration
    private let candidates: [String]
    private var resolvedPath: String?

    init(timeout: Duration = .seconds(20),
         candidates: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]) {
        self.timeout = timeout
        self.candidates = candidates
    }

    func availability() async -> GitHubAvailability {
        guard await ghPath() != nil else { return .notInstalled }
        do {
            let data = try await run(["auth", "status", "--hostname", "github.com", "--json", "hosts"])
            if let login = GHJSON.activeLogin(fromAuthStatus: data) { return .available(login: login) }
            return .notSignedIn
        } catch let error as GitHubError {
            switch error {
            case .notSignedIn: return .notSignedIn
            case .offline: return .offline
            case .notInstalled: return .notInstalled
            default: return await loginFromAPI() ?? .error(error.localizedDescription)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// For gh versions whose `auth status` has no `--json`.
    private func loginFromAPI() async -> GitHubAvailability? {
        guard let data = try? await run(["api", "user", "--jq", ".login"]) else { return nil }
        let login = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : .available(login: login)
    }

    func pullRequest(_ ref: PullRequestReference) async throws -> PullRequest {
        let data = try await run(["pr", "view", ref.url, "--json", PullRequest.viewFields])
        return try GHJSON.pullRequest(from: data)
    }

    func pullRequests(head branch: String, in repo: GitHubRepoRef) async throws -> [PullRequest] {
        let data = try await run(["pr", "list", "--head", branch, "--repo", repo.slug, "--state", "all",
                                  "--limit", "20", "--json", PullRequest.listFields])
        return try GHJSON.pullRequests(from: data)
    }

    // MARK: - Running gh

    private func run(_ arguments: [String]) async throws -> Data {
        guard let gh = await ghPath() else { throw GitHubError.notInstalled }
        let output: ProcessRunner.Output
        do {
            output = try await ProcessRunner.run(gh, arguments, environment: environment(gh: gh), timeout: timeout)
        } catch ProcessRunner.Failure.timedOut {
            throw GitHubError.timedOut
        } catch {
            resolvedPath = nil
            throw GitHubError.notInstalled
        }
        guard output.status == 0 else { throw GitHubError.fromGH(stderr: output.stderr, status: output.status) }
        return output.stdout
    }

    private func environment(gh: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let ghDirectory = URL(fileURLWithPath: gh).deletingLastPathComponent().path
        env["PATH"] = ([ghDirectory] + (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["GH_SPINNER_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        env["CLICOLOR"] = "0"
        return env
    }

    private func ghPath() async -> String? {
        if let resolvedPath, FileManager.default.isExecutableFile(atPath: resolvedPath) { return resolvedPath }
        let fileManager = FileManager.default
        var path = candidates.first { fileManager.isExecutableFile(atPath: $0) }
        if path == nil {
            let shell = ShellEnvironment.loginShell(from: ProcessInfo.processInfo.environment)
            let output = try? await ProcessRunner.run(shell, ["-l", "-c", "command -v gh"], timeout: .seconds(10))
            let found = output?.stdoutText.split(separator: "\n").last.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if let found, found.hasPrefix("/"), fileManager.isExecutableFile(atPath: found) { path = found }
        }
        resolvedPath = path
        return path
    }
}

/// Decoding gh's `--json` output.
enum GHJSON {
    static func pullRequest(from data: Data) throws -> PullRequest {
        do {
            return try JSONDecoder().decode(PullRequest.self, from: data)
        } catch {
            throw GitHubError.failed("Unexpected gh output: \(error.localizedDescription)")
        }
    }

    static func pullRequests(from data: Data) throws -> [PullRequest] {
        do {
            return try JSONDecoder().decode([PullRequest].self, from: data)
        } catch {
            throw GitHubError.failed("Unexpected gh output: \(error.localizedDescription)")
        }
    }

    /// The active github.com login from `gh auth status --json hosts`.
    static func activeLogin(fromAuthStatus data: Data) -> String? {
        struct Status: Decodable {
            struct Account: Decodable {
                var state: String?
                var active: Bool?
                var login: String?
            }
            var hosts: [String: [Account]]
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: data),
              let accounts = status.hosts["github.com"] else { return nil }
        let usable = accounts.filter { $0.state == nil || $0.state == "success" }
        return (usable.first { $0.active == true } ?? usable.first)?.login
    }
}
