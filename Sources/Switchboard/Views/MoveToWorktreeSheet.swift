import SwiftUI

/// "Move to Worktree…": pick the repo the session continues in.
struct MoveToWorktreeSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let rowID: UUID

    @State private var selection: Repo?

    private var session: Session? { store.sessions.first { $0.id == rowID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to Worktree").font(.headline)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(store.repos, selection: $selection) { repo in
                Label(repo.relativePath, systemImage: "arrow.triangle.branch").tag(repo)
            }
            .frame(minHeight: 220)
            .overlay {
                if store.repos.isEmpty {
                    Text(store.isScanningRepos ? "Scanning…" : "No repos found in the home folder")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") { move() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil || session?.canMoveToWorktree != true)
            }
        }
        .padding(16)
        .frame(width: 460)
        .task { await store.refreshRepos() }
    }

    private var explanation: String {
        guard let session else { return "" }
        let summary = session.agentConversationID != nil
            && HandoverCommand.summaryArguments(agent: session.agent, conversationID: "x") != nil
        let carried = summary ? "the ticket and a summary of this conversation" : "the ticket"
        return "Starts a fresh \(session.agent.displayName) session in a new worktree of the chosen repo "
            + "with \(carried), and replaces this row's terminal with it. This conversation is left as it is."
    }

    private func move() {
        guard let repo = selection else { return }
        dismiss()
        Task { await store.moveToWorktree(rowID, repo: repo) }
    }
}
