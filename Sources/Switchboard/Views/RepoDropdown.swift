import SwiftUI

/// Where ticket sessions start: "None" (a temp planning folder) or a repo.
struct RepoDropdown: View {
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Menu {
            Picker("Start ticket sessions in", selection: $settings.ticketRepoPath) {
                Text("None (plan in a temp folder)").tag(String?.none)
                if !store.repos.isEmpty { Divider() }
                ForEach(store.repos) { repo in
                    Text(repo.relativePath).tag(Optional(repo.url.path))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(label, systemImage: settings.ticketRepoPath == nil ? "tray" : "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Where new ticket sessions start")
        .task { await store.refreshRepos() }
    }

    private var label: String {
        guard let path = settings.ticketRepoPath else { return "No repo" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

extension AppSettings {
    /// The dropdown's repo, if it still exists on disk.
    var ticketRepo: Repo? {
        guard let path = ticketRepoPath, RepoScanner.isGitRepo(URL(fileURLWithPath: path)) else { return nil }
        let url = URL(fileURLWithPath: path)
        let home = homeFolder.standardizedFileURL.path + "/"
        let relative = url.path.hasPrefix(home) ? String(url.path.dropFirst(home.count)) : url.lastPathComponent
        return Repo(url: url, relativePath: relative)
    }
}
