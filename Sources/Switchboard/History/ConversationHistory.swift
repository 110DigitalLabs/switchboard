import Foundation

/// Lists recent conversations from the agents' own history folders:
///
/// - Claude Code: `<config>/projects/<folder>/<id>.jsonl`, one JSON object
///   per line, carrying `cwd`, `entrypoint`, user messages and title records.
/// - Codex: `<CODEX_HOME>/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`, whose
///   first line is `session_meta` with `id`, `cwd` and `source`; thread names
///   live in `<CODEX_HOME>/session_index.jsonl`.
///
/// Both formats are the agents' own and undocumented, so reading is lenient:
/// a file that does not parse is skipped. Transcripts run to hundreds of
/// megabytes, so only the newest files are opened, and of each only the head
/// (folder, first prompt) and the tail (latest title).
enum ConversationHistory {
    struct Locations: Sendable {
        var claudeProjects: URL
        var codexSessions: URL
        var codexIndex: URL

        static func standard(environment: [String: String] = ProcessInfo.processInfo.environment,
                             home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Locations {
            let claude = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude")
            let codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex")
            return Locations(claudeProjects: claude.appendingPathComponent("projects"),
                             codexSessions: codex.appendingPathComponent("sessions"),
                             codexIndex: codex.appendingPathComponent("session_index.jsonl"))
        }
    }

    static let headBytes = 64 * 1024
    static let tailBytes = 256 * 1024

    /// Newest first, at most `limit`, leaving out conversations whose folder
    /// no longer exists (the agent resumes by folder).
    static func recent(limit: Int = 100, in locations: Locations = .standard(),
                       directoryExists: (String) -> Bool = SessionLaunch.directoryExists) -> [PastConversation] {
        let claude = firstConversations(in: claudeTranscripts(in: locations.claudeProjects), limit: limit,
                                        directoryExists: directoryExists) {
            claudeConversation(at: $0, modified: $1)
        }
        let names = codexThreadNames(at: locations.codexIndex)
        let codex = firstConversations(in: files(under: locations.codexSessions), limit: limit,
                                       directoryExists: directoryExists) {
            codexConversation(at: $0, modified: $1, names: names)
        }
        return (claude + codex)
            .sorted { ($0.lastActive, $0.id) > ($1.lastActive, $1.id) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Claude Code

    /// `<projects>/<folder>/<id>.jsonl` only; sub-agent transcripts sit
    /// deeper and are not conversations of their own.
    static func claudeTranscripts(in projects: URL) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    static func claudeConversation(at url: URL, modified: Date) -> PastConversation? {
        guard let (head, tail) = headAndTail(of: url) else { return nil }
        return claudeConversation(id: url.deletingPathExtension().lastPathComponent,
                                  head: head, tail: tail, modified: modified)
    }

    /// nil for transcripts without a folder and for headless runs
    /// (`claude -p`, the SDKs), which have no session to go back to.
    static func claudeConversation(id: String, head: Data, tail: Data, modified: Date) -> PastConversation? {
        var directory: String?
        var entrypoint: String?
        var firstPrompt: String?
        for object in jsonLines(head) {
            if directory == nil, let cwd = object["cwd"] as? String, !cwd.isEmpty {
                directory = cwd
                entrypoint = object["entrypoint"] as? String
            }
            if firstPrompt == nil, object["type"] as? String == "user", object["isMeta"] as? Bool != true,
               let text = userText(object["message"]) {
                firstPrompt = text
            }
            if directory != nil, firstPrompt != nil { break }
        }
        guard let directory, !(entrypoint?.hasPrefix("sdk") ?? false) else { return nil }
        let late = ClaudeTranscript.titles(from: tail)
        let early = ClaudeTranscript.titles(from: head)
        return PastConversation(agent: .claudeCode, conversationID: id, directory: directory,
                                title: late.custom ?? early.custom ?? late.generated ?? early.generated,
                                firstPrompt: firstPrompt, lastActive: modified)
    }

    /// A typed prompt: plain text, not a tool result or a command wrapper
    /// such as `<command-name>`.
    private static func userText(_ message: Any?) -> String? {
        let content = (message as? [String: Any])?["content"]
        let text: String? = if let string = content as? String {
            string
        } else if let blocks = content as? [[String: Any]] {
            blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        } else {
            nil
        }
        guard let line = text?.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespaces), !line.isEmpty, !line.hasPrefix("<") else { return nil }
        return String(line.prefix(200))
    }

    // MARK: Codex

    static func codexConversation(at url: URL, modified: Date, names: [String: String]) -> PastConversation? {
        guard url.pathExtension == "jsonl", let (head, _) = headAndTail(of: url, tail: 0, head: 512 * 1024)
        else { return nil }
        return codexConversation(head: head, modified: modified, names: names)
    }

    /// Interactive sessions only: `codex exec` and other non-interactive
    /// sources cannot be resumed into a terminal. The first line carries the
    /// full base instructions, so it can be large.
    static func codexConversation(head: Data, modified: Date, names: [String: String]) -> PastConversation? {
        guard let object = jsonLines(head).first, object["type"] as? String == "session_meta",
              let meta = object["payload"] as? [String: Any],
              let id = meta["id"] as? String, !id.isEmpty,
              let cwd = meta["cwd"] as? String, !cwd.isEmpty,
              ["cli", "vscode"].contains(meta["source"] as? String ?? "cli")
        else { return nil }
        return PastConversation(agent: .codex, conversationID: id, directory: cwd,
                                title: names[id], firstPrompt: nil, lastActive: modified)
    }

    /// Thread ID to name; a later line renames.
    static func codexThreadNames(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        var names: [String: String] = [:]
        for object in jsonLines(data) {
            if let id = object["id"] as? String,
               let name = (object["thread_name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }

    // MARK: Files

    private static func files(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    /// Reads files newest first until `limit` conversations are found.
    /// Headless runs can far outnumber interactive ones, so up to four times
    /// `limit` files are opened.
    private static func firstConversations(in urls: [URL], limit: Int, directoryExists: (String) -> Bool,
                                           read: (URL, Date) -> PastConversation?) -> [PastConversation] {
        let newest = urls.compactMap { url in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { (url: url, modified: $0) }
        }
        .sorted { $0.modified > $1.modified }
        var found: [PastConversation] = []
        for file in newest.prefix(limit * 4) {
            guard found.count < limit else { break }
            if let conversation = read(file.url, file.modified), directoryExists(conversation.directory) {
                found.append(conversation)
            }
        }
        return found
    }

    private static func headAndTail(of url: URL, tail tailSize: Int = tailBytes,
                                    head headSize: Int = headBytes) -> (Data, Data)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headSize) else { return nil }
        guard tailSize > 0, let size = try? handle.seekToEnd(), size > UInt64(headSize) else { return (head, Data()) }
        try? handle.seek(toOffset: size - min(size - UInt64(headSize), UInt64(tailSize)))
        return (head, (try? handle.readToEnd()) ?? Data())
    }

    /// Complete JSON objects, one per line; lines cut off by a slice fail to
    /// parse and are skipped.
    private static func jsonLines(_ data: Data) -> [[String: Any]] {
        data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
    }
}
