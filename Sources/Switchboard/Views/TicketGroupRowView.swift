import SwiftUI

/// Parent row for sessions sharing a ticket: the ticket ID and its PRs.
struct TicketGroupRowView: View {
    let group: SessionListLayout.TicketGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ticket")
                .foregroundStyle(.secondary)
            Text(group.ticketID)
                .fontWeight(.medium)
            Text("\(group.entries.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            PRIconsView(urls: group.prURLs)
        }
    }
}
