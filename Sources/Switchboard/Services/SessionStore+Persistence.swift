import Foundation

extension SessionStore {
    var persistedState: PersistedState {
        PersistedState(sessions: sessions, collapsedGroups: collapsedGroups, selectedID: selectedID)
    }

    /// Debounced; live-only changes (status text, activity) are not
    /// persisted, so they encode identically and skip the write.
    func scheduleSave() {
        guard file != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let file else { return }
        do {
            let data = try persistedState.encoded()
            guard data != lastSaved else { return }
            try file.write(data)
            lastSaved = data
        } catch {
            NSLog("Switchboard: could not save sessions: \(error)")
        }
    }
}
