import Foundation

/// Conversations whose agent is running right now, in some other terminal.
///
/// - Claude Code registers each live session as `<config>/sessions/<pid>.json`
///   (`pid`, `sessionId`, `startedAt`, `kind`). A file can outlive its
///   process, and a pid can be reused, so an entry counts only while that
///   pid is running and started when the entry says it did.
/// - Codex has no registry. A running `codex` is matched to its conversation
///   by `codex resume <id>` in its arguments, or else to the newest rollout
///   in its working folder created since it started. A codex that has not
///   been sent a prompt has no rollout yet, and nothing to resume.
/// - An agent started by hand in one of Switchboard's own terminals is not
///   elsewhere, even though no hook told its row about it, so anything
///   descended from this app is left out.
enum ActiveConversations {
    /// A process from `ps`.
    struct RunningProcess: Equatable, Sendable {
        var pid: Int32
        var parent: Int32
        var started: Date
        var arguments: [String]
    }

    /// One `<pid>.json` from Claude Code's session registry.
    struct ClaudeEntry: Equatable, Sendable {
        var pid: Int32
        var sessionID: String
        var started: Date
        var interactive: Bool
    }

    /// A Codex rollout file's identity, from its first line.
    struct CodexRollout: Equatable, Sendable {
        var url: URL
        var id: String
        var directory: String
        var modified: Date
    }

    /// Newest first, leaving out conversations whose folder no longer exists
    /// (the agent resumes by folder).
    static func list(in locations: ConversationHistory.Locations = .standard(),
                     processes allProcesses: [RunningProcess] = runningProcesses(),
                     excludingDescendantsOf root: Int32 = ProcessInfo.processInfo.processIdentifier,
                     workingDirectories: ([RunningProcess]) -> [Int32: String] = workingDirectories(of:),
                     directoryExists: (String) -> Bool = SessionLaunch.directoryExists) -> [PastConversation] {
        let mine = descendants(of: root, in: allProcesses)
        let processes = allProcesses.filter { !mine.contains($0.pid) }
        let claudeIDs = liveClaudeSessions(registry: claudeRegistry(in: locations.claudeSessions),
                                           processes: processes)
        let claude = ConversationHistory.claudeTranscripts(in: locations.claudeProjects)
            .filter { claudeIDs.contains($0.deletingPathExtension().lastPathComponent) }
            .compactMap { url in modified(url).flatMap { ConversationHistory.claudeConversation(at: url, modified: $0) } }

        let codexProcesses = interactiveCodex(processes)
        var codex: [PastConversation] = []
        if !codexProcesses.isEmpty {
            let earliest = codexProcesses.map(\.started).min() ?? Date()
            let rollouts = codexRollouts(under: locations.codexSessions, modifiedSince: earliest)
            let byID = codexConversationIDs(for: codexProcesses, directories: workingDirectories(codexProcesses),
                                            rollouts: rollouts)
            let names = ConversationHistory.codexThreadNames(at: locations.codexIndex)
            codex = rollouts.filter { byID.contains($0.id) }.compactMap {
                ConversationHistory.codexConversation(at: $0.url, modified: $0.modified, names: names)
            }
        }
        return (claude + codex)
            .filter { directoryExists($0.directory) }
            .sorted { ($0.lastActive, $0.id) > ($1.lastActive, $1.id) }
    }

    // MARK: Claude Code

    static func liveClaudeSessions(registry: [ClaudeEntry], processes: [RunningProcess]) -> Set<String> {
        let started = Dictionary(processes.map { ($0.pid, $0.started) }, uniquingKeysWith: { first, _ in first })
        return Set(registry.filter { entry in
            guard entry.interactive, let processStart = started[entry.pid] else { return false }
            // `ps` reports whole seconds; the registry is written once the
            // agent has loaded, which can take a while on a slow start.
            return abs(entry.started.timeIntervalSince(processStart)) < 120
        }.map(\.sessionID))
    }

    static func claudeRegistry(in folder: URL) -> [ClaudeEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap(claudeEntry)
        }
    }

    static func claudeEntry(_ data: Data) -> ClaudeEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (object["pid"] as? NSNumber)?.int32Value,
              let id = object["sessionId"] as? String, !id.isEmpty,
              let startedAt = (object["startedAt"] as? NSNumber)?.doubleValue
        else { return nil }
        let kind = object["kind"] as? String ?? "interactive"
        return ClaudeEntry(pid: pid, sessionID: id, started: Date(timeIntervalSince1970: startedAt / 1000),
                           interactive: kind == "interactive")
    }

    // MARK: Codex

    private static let codexBatchCommands: Set<String> = [
        "exec", "e", "review", "app-server", "mcp", "mcp-server", "login", "logout", "apply", "a",
        "completion", "sandbox", "debug", "cloud", "proto", "responses-api-proxy", "features", "help",
    ]

    /// The TUI processes: `codex`, `codex <prompt>`, `codex resume …`. A codex
    /// started by another codex is a helper, not a session.
    static func interactiveCodex(_ processes: [RunningProcess]) -> [RunningProcess] {
        let codexPIDs = Set(processes.filter(isCodex).map(\.pid))
        return processes.filter { process in
            guard isCodex(process), !codexPIDs.contains(process.parent) else { return false }
            guard let first = process.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return true }
            return !codexBatchCommands.contains(first)
        }
    }

    private static func isCodex(_ process: RunningProcess) -> Bool {
        guard let first = process.arguments.first else { return false }
        return URL(fileURLWithPath: first).lastPathComponent == "codex"
    }

    /// `codex resume <id>` names its conversation; any other codex takes the
    /// most recently written rollout in its folder created since it started.
    static func codexConversationIDs(for processes: [RunningProcess], directories: [Int32: String],
                                     rollouts: [CodexRollout]) -> Set<String> {
        var ids: Set<String> = []
        for process in processes {
            let arguments = Array(process.arguments.dropFirst())
            if let index = arguments.firstIndex(of: "resume"),
               let id = arguments[(index + 1)...].first(where: { !$0.hasPrefix("-") }) {
                ids.insert(id)
                continue
            }
            guard let directory = directories[process.pid] else { continue }
            let mine = rollouts.filter { rollout in
                rollout.directory == directory && !ids.contains(rollout.id)
                    && (rolloutCreated(rollout.url) ?? rollout.modified) >= process.started.addingTimeInterval(-5)
            }
            if let newest = mine.max(by: { $0.modified < $1.modified }) { ids.insert(newest.id) }
        }
        return ids
    }

    /// From `rollout-2026-11-18T11-19-37-<id>.jsonl`, in local time.
    static func rolloutCreated(_ url: URL) -> Date? {
        let name = url.lastPathComponent
        guard name.hasPrefix("rollout-"), name.count >= 27 else { return nil }
        let stamp = name.dropFirst("rollout-".count).prefix(19)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: String(stamp))
    }

    private static func codexRollouts(under root: URL, modifiedSince: Date) -> [CodexRollout] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [
            .contentModificationDateKey,
        ]) else { return [] }
        return walker.compactMap { $0 as? URL }.compactMap { url in
            guard url.pathExtension == "jsonl", let modified = modified(url), modified >= modifiedSince,
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 512 * 1024),
                  let line = head.split(separator: UInt8(ascii: "\n")).first,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let meta = object["payload"] as? [String: Any],
                  let id = meta["id"] as? String, let cwd = meta["cwd"] as? String
            else { return nil }
            return CodexRollout(url: url, id: id, directory: cwd, modified: modified)
        }
    }

    // MARK: Processes

    /// Every process below `root`, at any depth.
    static func descendants(of root: Int32, in processes: [RunningProcess]) -> Set<Int32> {
        let children = Dictionary(grouping: processes, by: \.parent)
        var found: Set<Int32> = []
        var pending = [root]
        while let pid = pending.popLast() {
            for child in children[pid] ?? [] where found.insert(child.pid).inserted {
                pending.append(child.pid)
            }
        }
        return found
    }

    static func runningProcesses() -> [RunningProcess] {
        guard let output = try? ProcessRunner.runBlocking("/bin/ps", ["-axww", "-o", "pid=,ppid=,lstart=,args="],
                                                          directory: nil, environment: nil, timeout: .seconds(5))
        else { return [] }
        return parseProcesses(output.stdoutText)
    }

    /// `ps -o pid=,ppid=,lstart=,args=` lines: pid, parent, a five-word start
    /// time such as `Wed Nov 18 17:19:29 2026` in local time, then arguments.
    static func parseProcesses(_ text: String) -> [RunningProcess] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 8, let pid = Int32(words[0]), let parent = Int32(words[1]),
                  let started = formatter.date(from: words[2...6].joined(separator: " "))
            else { return nil }
            return RunningProcess(pid: pid, parent: parent, started: started, arguments: Array(words[7...]))
        }
    }

    static func workingDirectories(of processes: [RunningProcess]) -> [Int32: String] {
        let pids = processes.map { String($0.pid) }.joined(separator: ",")
        guard let output = try? ProcessRunner.runBlocking("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fn", "-p", pids],
                                                          directory: nil, environment: nil, timeout: .seconds(5))
        else { return [:] }
        return parseWorkingDirectories(output.stdoutText)
    }

    /// `lsof -Fn` output: a `p<pid>` line, then `n<path>` for its cwd.
    static func parseWorkingDirectories(_ text: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") {
                pid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let current = pid {
                result[current] = String(line.dropFirst())
            }
        }
        return result
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
