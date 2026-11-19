import SwiftUI

/// Parent row for a ticket: its ID, title and PRs, and a "+" that starts
/// another session on it. Assigned tickets without sessions show dimmed.
struct TicketGroupRowView: View {
    let group: SessionListLayout.TicketGroup
    var addHelp: String
    var onAdd: () -> Void
    @Environment(\.sessionListFonts) private var fonts

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ticket")
                .font(fonts.title)
                .foregroundStyle(.secondary)
            Text(group.ticketID)
                .font(fonts.title)
                .fontWeight(.medium)
            if let title = group.title {
                Text(title)
                    .font(fonts.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !group.entries.isEmpty {
                Text("\(group.entries.count)")
                    .font(fonts.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            PRIconsView(urls: group.prURLs)
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(addHelp)
        }
        .opacity(group.unstartedIssue == nil ? 1 : 0.6)
    }
}
