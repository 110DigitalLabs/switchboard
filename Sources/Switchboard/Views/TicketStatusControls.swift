import SwiftUI

/// The status bar's ticket ID (opens it in Linear) and status menu, which
/// lists every workflow state of the ticket's team. Greyed out while
/// Linear is signed out or offline.
struct TicketStatusControls: View {
    @Environment(LinearAccount.self) private var linear
    @Environment(TicketStatusModel.self) private var model
    @Environment(\.openURL) private var openURL
    let ticketID: String

    var body: some View {
        let issue = model.issue(ticketID)
        let states = model.states(for: ticketID)
        HStack(spacing: 6) {
            Button(ticketID) {
                if let url = issue?.url { openURL(url) }
            }
            .buttonStyle(.link)
            .disabled(!linear.isConnected || issue?.url == nil)
            .help(issue.map { "\($0.title) — open in Linear" } ?? "Open in Linear")

            Menu {
                ForEach(states, id: \.self) { state in
                    Button {
                        guard let service = linear.service else { return }
                        Task { await model.setState(state, for: ticketID, service: service) }
                    } label: {
                        if model.isCurrent(state, for: ticketID) {
                            Label(state.name, systemImage: "checkmark")
                        } else {
                            Text(state.name)
                        }
                    }
                }
            } label: {
                Text(issue?.state?.name ?? "Status")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!linear.isConnected || states.isEmpty || model.updating != nil)
            .help(model.errorMessage ?? "Set the ticket's status in Linear")
            if model.updating == ticketID {
                ProgressView().controlSize(.mini)
            }
        }
        .task(id: LoadKey(ticketID: ticketID, connected: linear.isConnected)) {
            guard linear.isConnected, let service = linear.service else { return }
            await model.load(ticketID, service: service)
        }
    }

    private struct LoadKey: Equatable {
        var ticketID: String
        var connected: Bool
    }
}
