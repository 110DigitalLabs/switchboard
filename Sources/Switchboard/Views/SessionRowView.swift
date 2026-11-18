import SwiftUI

struct SessionRowView: View {
    let session: Session
    /// The ticket with its -A/-B suffix when several sessions share it.
    var ticketLabel: String?
    /// "Move to worktree" progress, while it runs.
    var handoverProgress: String?

    private var title: String { session.agentTitle ?? ticketLabel ?? session.title }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .lineLimit(1)
                    if let ticketLabel, session.agentTitle != nil {
                        Text(ticketLabel)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    } else if let ticketTitle = session.ticketTitle, session.agentTitle == nil {
                        Text(ticketTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let handoverProgress {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(handoverProgress)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let status = session.statusText {
                    Text(status)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
            PRIconsView(urls: session.prURLs)
            if session.hasBadge {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
            StateIndicator(state: session.workingState)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let agent = session.agentModel.map { "\(session.agent.displayName) (\($0))" } ?? session.agent.displayName
        return "\(abbreviated(session.folderPath)) · \(agent)"
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

private struct StateIndicator: View {
    let state: WorkingState

    var body: some View {
        if state == .exited {
            Text("Exited")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        } else {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .help(state.label)
                .accessibilityLabel(state.label)
        }
    }

    private var color: Color {
        switch state {
        case .idle: .gray.opacity(0.5)
        case .working, .subagentsRunning: .blue
        case .needsInput: .orange
        case .finished: .green
        case .exited: .clear
        }
    }
}

extension Session {
    /// The kind's icon; PR reviews in their own folder get an eye.
    var iconName: String { ReviewSessions.isReviewFolder(self) ? "eye" : kind.iconName }
}

extension SessionKind {
    var iconName: String {
        switch self {
        case .worktree: "arrow.triangle.branch"
        case .folder: "folder"
        case .scratch: "note.text"
        case .temp: "clock"
        }
    }
}
