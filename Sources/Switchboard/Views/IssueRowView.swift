import SwiftUI

/// One Linear issue in the search results or the assigned list.
struct IssueRowView: View {
    let issue: LinearIssue
    var actionHelp: String
    var action: () -> Void
    @Environment(\.sessionListFonts) private var fonts

    var body: some View {
        HStack(spacing: 6) {
            Text(issue.identifier)
                .font(fonts.detail)
                .foregroundStyle(.secondary)
            Text(issue.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let state = issue.state?.name {
                Text(state)
                    .font(fonts.detail)
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
