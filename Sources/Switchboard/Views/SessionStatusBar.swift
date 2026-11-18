import AppKit
import SwiftUI

/// A thin bar under the terminal: agent and model, repo/branch (or the folder
/// outside git), ticket with its status toggle, and PRs.
struct SessionStatusBar: View {
    let session: Session

    @State private var checkout: Checkout?

    private var path: String { session.workingDirectory ?? session.folderPath }

    var body: some View {
        HStack(spacing: 12) {
            Label(agentText, systemImage: "cpu")
                .lineLimit(1)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Label(locationText, systemImage: checkout == nil ? session.iconName : "arrow.triangle.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.borderless)
            .help("Reveal \(path) in Finder")
            if let ticketID = session.ticketID {
                TicketStatusControls(ticketID: ticketID)
            }
            Spacer(minLength: 4)
            PRIconsView(urls: session.prURLs)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
        // Re-read after each state change so a branch switch shows up.
        .task(id: RefreshKey(path: path, state: session.workingState)) {
            checkout = await Checkout.load(path)
        }
    }

    private var agentText: String {
        session.agentModel.map { "\(session.agent.displayName) · \($0)" } ?? session.agent.displayName
    }

    private var locationText: String {
        checkout?.label ?? (path as NSString).abbreviatingWithTildeInPath
    }

    private struct RefreshKey: Hashable {
        let path: String
        let state: WorkingState
    }
}

/// The repo and branch a folder is checked out on.
struct Checkout: Equatable, Sendable {
    let repo: String
    let branch: String?

    var label: String { branch.map { "\(repo)/\($0)" } ?? repo }

    static func load(_ path: String, git: GitInfo = GitInfo(timeout: .seconds(2))) async -> Checkout? {
        guard let repo = await git.repoName(in: path) else { return nil }
        return Checkout(repo: repo, branch: await git.branch(in: path))
    }
}
