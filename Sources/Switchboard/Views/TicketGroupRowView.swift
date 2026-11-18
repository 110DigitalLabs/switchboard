import SwiftUI

/// Parent row for sessions sharing a ticket: the ticket ID and its PRs.
struct TicketGroupRowView: View {
    let group: SessionListLayout.TicketGroup
    @Environment(\.sessionListFonts) private var fonts

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ticket")
                .font(fonts.title)
                .foregroundStyle(.secondary)
            Text(group.ticketID)
                .font(fonts.title)
                .fontWeight(.medium)
            Text("\(group.entries.count)")
                .font(fonts.detail)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            PRIconsView(urls: group.prURLs)
        }
    }
}
