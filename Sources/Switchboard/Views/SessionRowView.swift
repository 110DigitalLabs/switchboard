import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .lineLimit(1)
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

    private var iconName: String {
        switch session.kind {
        case .worktree: "arrow.triangle.branch"
        case .folder: "folder"
        case .scratch: "note.text"
        case .temp: "clock"
        }
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
