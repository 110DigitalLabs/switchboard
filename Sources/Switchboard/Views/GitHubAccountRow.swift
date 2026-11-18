import SwiftUI

/// GitHub status in Settings. PR data comes from the gh CLI; signing in
/// runs `gh auth login --web` in a new scratch terminal.
struct GitHubAccountRow: View {
    @Environment(GitHubAccount.self) private var github
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LabeledContent {
            switch github.availability {
            case nil:
                ProgressView().controlSize(.small)
            case .available, .offline, .error:
                Button("Check Again") { Task { await github.checkAvailability() } }
            case .notSignedIn:
                HStack {
                    Button("Check Again") { Task { await github.checkAvailability() } }
                    Button("Sign In…") { signIn() }
                }
            case .notInstalled:
                Link("Get gh", destination: URL(string: "https://cli.github.com")!)
            }
        } label: {
            Text("GitHub")
            Text(statusLine)
                .foregroundStyle(github.isAvailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        }
        .task { await github.checkAvailability() }
    }

    private var statusLine: String {
        switch github.availability {
        case nil: "Checking gh…"
        case .available(let login): "Signed in as \(login) via gh"
        case .notSignedIn: "gh is not signed in. Sign In opens `gh auth login --web` in a terminal."
        case .notInstalled: "Not available: install the GitHub CLI (brew install gh)."
        case .offline: "GitHub is unreachable"
        case .error(let message): message
        }
    }

    private func signIn() {
        store.startCommandSession("gh auth login --web --hostname github.com", title: "GitHub sign-in",
                                  agent: settings.defaultAgent)
        openWindow(id: "main")
    }
}
