import SwiftUI

/// "Assigned to me": assigned issues without a local session yet.
struct AssignedTicketsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LinearAccount.self) private var linear
    let actions: TicketActions

    static let collapseKey = "assigned-to-me"

    var body: some View {
        let issues = TicketSessions.unstarted(linear.assignedIssues, sessions: store.sessions)
        DisclosureGroup(isExpanded: Binding(
            get: { linear.isConnected && !store.isCollapsed(Self.collapseKey) },
            set: { store.setCollapsed(Self.collapseKey, !$0) }
        )) {
            if issues.isEmpty {
                Text("Nothing new assigned").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(issues) { issue in
                            IssueRowView(issue: issue, actionHelp: actions.startHelp) { actions.start(issue) }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .fixedSize(horizontal: false, vertical: issues.count <= 5)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Assigned to me").font(.caption.weight(.semibold))
                if linear.isConnected {
                    Text("\(issues.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .disabled(!linear.isConnected)
    }
}
