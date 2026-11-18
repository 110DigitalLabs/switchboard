import Foundation

/// Closing rows, keeping temp folders, and the N-day cleanup of kept rows.
extension SessionStore {
    /// "Close Session": temp and scratch rows ask whether to delete their
    /// folder; worktree rows (the agent handles worktree cleanup) and plain
    /// folder rows close without touching anything on disk.
    func requestClose(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if TempCleanupPolicy.asksBeforeClosing(session) {
            closeRequestID = id
        } else if !session.isKept {
            close(id)
        }
    }

    /// Delete: end the terminal, trash the folder (if safe), drop the row.
    func closeDeletingFolder(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        terminals.remove(id)
        if let refusal = trashFolder(of: session) {
            errorMessage = "Kept \(session.folderPath): \(refusal)"
        }
        close(id)
    }

    /// Keep: end the terminal and leave the row, dimmed, in the Temp group.
    func closeKeepingFolder(_ id: UUID, now: Date = Date()) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        terminals.remove(id)
        session.closedAt = now
        session.activity = RowActivity()
        session.hasBadge = false
        session.statusText = nil
        update(session)
        notifier?.clear(rowID: id)
        if selectedID == id { selectedID = layout.visibleOrder.first }
    }

    /// Brings a kept row back as a live row, resuming its conversation.
    func reopenKept(_ id: UUID) {
        guard var session = sessions.first(where: { $0.id == id }), session.isKept else { return }
        session.closedAt = nil
        update(session)
        openTerminal(for: session, launch: .reopen(session, hooks: terminals.hooks))
        selectedID = id
    }

    /// "Delete now" on a kept row.
    func deleteKept(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isKept else { return }
        closeDeletingFolder(id)
    }

    /// Trashes the folders of kept rows past the settings' age and drops
    /// the rows. Returns the IDs removed.
    @discardableResult
    func runTempCleanup(now: Date = Date()) -> [UUID] {
        let expired = TempCleanupPolicy.expired(sessions, now: now, days: settings.tempCleanupDays)
        for id in expired {
            guard let session = sessions.first(where: { $0.id == id }) else { continue }
            _ = trashFolder(of: session)
            close(id)
        }
        if !expired.isEmpty { NSLog("Switchboard: cleaned up \(expired.count) kept temp session(s)") }
        return expired
    }

    /// Runs cleanup now and then every six hours for the app's lifetime.
    func startTempCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.runTempCleanup()
                try? await Task.sleep(for: .seconds(TempCleanupPolicy.interval))
            }
        }
    }

    /// Moves a row's folder to the Trash when `TempFolderSafety` allows it
    /// and no other row uses that folder. Returns why it was not deleted, or
    /// nil when it was trashed or is already gone.
    private func trashFolder(of session: Session) -> String? {
        let refusal: String
        switch TempFolderSafety.check(session.folderPath, home: settings.homeFolder) {
        case .missing:
            return nil
        case .refused(let reason):
            refusal = reason
        case .deletable(let url):
            let sharedBy = sessions.contains { other in
                other.id != session.id
                    && [other.folderPath, other.workingDirectory].compactMap { $0 }.contains {
                        Self.overlaps($0, url.path)
                    }
            }
            if sharedBy {
                refusal = "another session uses it"
            } else {
                do {
                    try trashItem(url)
                    NSLog("Switchboard: moved \(url.path) to the Trash")
                    return nil
                } catch {
                    refusal = error.localizedDescription
                }
            }
        }
        NSLog("Switchboard: refused to delete \(session.folderPath): \(refusal)")
        return refusal
    }

    /// Whether `path` (resolved when it exists) is `folder`, inside it, or
    /// contains it: trashing `folder` would pull the floor from under it.
    nonisolated static func overlaps(_ path: String, _ folder: String) -> Bool {
        let other = TempFolderSafety.realPath(path) ?? (path as NSString).standardizingPath
        return other == folder || other.hasPrefix(folder + "/") || folder.hasPrefix(other + "/")
            || other == "/"
    }
}
