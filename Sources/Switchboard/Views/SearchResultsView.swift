import SwiftUI

/// Results under the search box while it has text.
struct SearchResultsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LinearAccount.self) private var linear
    @Environment(\.sessionListFonts) private var fonts
    let search: TicketSearchModel
    let actions: TicketActions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch search.input {
            case .empty:
                EmptyView()
            case .pullRequest(let ref):
                PullRequestSearchRow(ref: ref, actions: actions)
            case .ticket(let id):
                if linear.isConnected { ticketResults(id) } else { signedOutNote }
            case .text:
                if linear.isConnected { textResults } else { signedOutNote }
            }
        }
    }

    private var signedOutNote: some View {
        Text("Ticket search needs Linear.").foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func ticketResults(_ id: String) -> some View {
        let existing = TicketSessions.existing(for: id, in: store.sessions)
        let labels = TicketSuffixes.labels(for: store.sessions)
        if !existing.isEmpty {
            Text("Sessions on \(id)").font(fonts.detail).foregroundStyle(.secondary)
            ForEach(existing) { session in
                ExistingSessionRow(session: session, label: labels[session.id] ?? id)
            }
        }
        switch search.results {
        case .loading:
            ProgressView().controlSize(.small)
        case .issue(let issue) where issue.identifier == id:
            if existing.isEmpty {
                IssueRowView(issue: issue, actionHelp: actions.startHelp) { actions.start(issue) }
            } else {
                Text(issue.title).foregroundStyle(.secondary).lineLimit(1)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var textResults: some View {
        switch search.results {
        case .loading:
            ProgressView().controlSize(.small)
        case .issues(let issues) where issues.isEmpty:
            Text("No matching tickets").foregroundStyle(.secondary)
        case .issues(let issues):
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { issue in
                        IssueRowView(issue: issue, actionHelp: actions.startHelp) { actions.open(issue) }
                            .onTapGesture { actions.open(issue) }
                    }
                }
            }
            .frame(maxHeight: 220)
        case .failed(let message):
            Text(message).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// A local session already on the searched ticket, with "+" for another.
private struct ExistingSessionRow: View {
    @Environment(SessionStore.self) private var store
    let session: Session
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.iconName)
                .foregroundStyle(.secondary)
            Button(session.agentTitle.map { "\(label) · \($0)" } ?? label) {
                store.selectedID = session.id
            }
            .buttonStyle(.link)
            .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                store.addSibling(of: session.id)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Another session on this ticket, in the same kind of folder")
        }
    }
}
