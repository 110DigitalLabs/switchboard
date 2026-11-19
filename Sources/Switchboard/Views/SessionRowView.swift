import SwiftUI

struct SessionRowView: View {
    let session: Session
    /// The ticket with its -A/-B suffix when several sessions share it.
    var ticketLabel: String?
    /// "Move to worktree" progress, while it runs.
    var handoverProgress: String?
    /// "kept · deletes in N days" for a closed row whose folder was kept.
    var keptNote: String?
    /// N for the ⌘N shortcut that selects this row, when it has one.
    var shortcutNumber: Int?

    @Environment(\.sessionListFonts) private var fonts
    @Environment(\.terminalPalette) private var palette

    private var title: String { session.agentTitle ?? ticketLabel ?? session.title }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.iconName)
                .font(fonts.title)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(fonts.title)
                        .lineLimit(1)
                    if let ticketLabel, session.agentTitle != nil {
                        Text(ticketLabel)
                            .font(fonts.detailMonospaced)
                            .foregroundStyle(.secondary)
                    } else if let ticketTitle = session.ticketTitle, session.agentTitle == nil {
                        Text(ticketTitle)
                            .font(fonts.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let handoverProgress {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(handoverProgress)
                    }
                    .font(fonts.detail)
                    .foregroundStyle(.secondary)
                }
                Text(detailLine)
                    .font(fonts.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let keptNote {
                    Text(keptNote)
                        .font(fonts.detail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            PRIconsView(urls: session.prURLs)
            if session.hasBadge && keptNote == nil {
                Circle()
                    .fill(palette.red)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
            if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(fonts.detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Press ⌘\(shortcutNumber) to switch to this session")
            }
            if keptNote == nil {
                StateIndicator(state: session.workingState, palette: palette)
            }
        }
        .padding(.vertical, 2)
    }

    /// The agent's status line as the terminal shows it, else folder and agent.
    private var detailLine: AttributedString {
        session.statusLine.flatMap { ANSIText.firstLine(of: $0, palette: palette) }
            ?? AttributedString(subtitle)
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
    let palette: TerminalPalette

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
        case .idle: palette.dim
        case .working, .subagentsRunning: palette.cyan
        case .needsInput: palette.yellow
        case .finished: palette.green
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
