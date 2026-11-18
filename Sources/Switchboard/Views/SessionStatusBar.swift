import AppKit
import SwiftUI

/// A thin bar under the terminal: agent and model, folder, ticket with its
/// status toggle, and PRs.
struct SessionStatusBar: View {
    let session: Session

    private var path: String { session.workingDirectory ?? session.folderPath }

    var body: some View {
        HStack(spacing: 12) {
            Label(agentText, systemImage: "cpu")
                .lineLimit(1)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Label((path as NSString).abbreviatingWithTildeInPath, systemImage: session.iconName)
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
    }

    private var agentText: String {
        session.agentModel.map { "\(session.agent.displayName) · \($0)" } ?? session.agent.displayName
    }
}
