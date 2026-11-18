import Foundation

/// `sessions.json` in Switchboard's Application Support folder.
struct SessionFile: Sendable {
    let url: URL

    static func standard(name: String = "sessions.json") throws -> SessionFile {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return SessionFile(url: support.appendingPathComponent("Switchboard/\(name)"))
    }

    /// The saved state. A missing file is an empty state; a file that cannot
    /// be read as a state is moved aside to `sessions.corrupt-<time>.json`
    /// and also yields an empty state, so a bad file never blocks launch.
    func load(now: Date = Date()) -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        do {
            return try PersistedState.decode(data)
        } catch {
            let backup = backupURL(at: now)
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                NSLog("Switchboard: unreadable sessions file moved to \(backup.path): \(error)")
            } catch {
                NSLog("Switchboard: unreadable sessions file could not be moved aside: \(error)")
            }
            return PersistedState()
        }
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func backupURL(at date: Date) -> URL {
        let stamp = ScratchFolder.name(for: date)
        return url.deletingLastPathComponent().appendingPathComponent("sessions.corrupt-\(stamp).json")
    }
}
