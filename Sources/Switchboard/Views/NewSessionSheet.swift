import AppKit
import SwiftUI

/// The "+" picker: a repo, the scratch entry, or any other folder, plus agent.
struct NewSessionSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var filter = ""
    @State private var selection: PickerItem? = .scratch
    @State private var agent: Agent = .claudeCode

    private enum PickerItem: Hashable {
        case scratch
        case repo(Repo)
    }

    private var filteredRepos: [Repo] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.repos }
        return store.repos.filter { $0.relativePath.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Session").font(.headline)

            TextField("Filter repos", text: $filter)
                .textFieldStyle(.roundedBorder)

            List(selection: $selection) {
                Label("Scratch session", systemImage: "note.text")
                    .tag(PickerItem.scratch)
                Section(store.isScanningRepos && store.repos.isEmpty ? "Scanning…" : "Repos") {
                    ForEach(filteredRepos) { repo in
                        Label(repo.relativePath, systemImage: "arrow.triangle.branch")
                            .tag(PickerItem.repo(repo))
                    }
                }
            }
            .frame(minHeight: 280)
            .contextMenu(forSelectionType: PickerItem.self) { _ in
            } primaryAction: { _ in
                createSelected()
            }

            Picker("Agent", selection: $agent) {
                ForEach(Agent.allCases) { Text($0.displayName).tag($0) }
            }

            HStack {
                Button("Choose Other Folder…") { chooseFolder() }
                Button("Resume Existing…") {
                    dismiss()
                    // After this sheet is gone: one sheet at a time.
                    DispatchQueue.main.async { store.isResumePresented = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { createSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(width: 480)
        .onAppear { agent = settings.defaultAgent }
        .task { await store.refreshRepos() }
    }

    private func createSelected() {
        switch selection {
        case .scratch: create(.scratch)
        case .repo(let repo): create(.repo(repo))
        case nil: break
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.homeFolder
        panel.prompt = "Start Session"
        if panel.runModal() == .OK, let url = panel.url {
            create(.folder(url))
        }
    }

    private func create(_ target: NewSessionTarget) {
        store.create(target, agent: agent)
        dismiss()
    }
}
