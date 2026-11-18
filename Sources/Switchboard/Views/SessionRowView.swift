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
                Text("\(abbreviated(session.folderPath)) · \(session.agent.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
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
