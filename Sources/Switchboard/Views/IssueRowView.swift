import SwiftUI

/// One Linear issue in the search results or the assigned list.
struct IssueRowView: View {
    let issue: LinearIssue
    var actionHelp: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(issue.identifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let state = issue.state?.name {
                Text(state)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: action) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(actionHelp)
        }
        .contentShape(Rectangle())
    }
}
