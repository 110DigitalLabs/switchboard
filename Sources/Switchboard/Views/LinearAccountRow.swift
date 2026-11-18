import SwiftUI

/// Sign in / sign out and connection status for Linear, in Settings.
struct LinearAccountRow: View {
    @Environment(LinearAccount.self) private var account

    var body: some View {
        LabeledContent {
            switch account.status {
            case .signingIn:
                HStack {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { account.cancelSignIn() }
                }
            case .signedOut, .error:
                Button("Sign In…") { Task { await account.signIn() } }
            case .signedIn, .offline:
                Button("Sign Out") { Task { await account.signOut() } }
            }
        } label: {
            Text("Linear")
            Text(statusLine)
                .foregroundStyle(statusIsProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
    }

    private var statusLine: String {
        switch account.status {
        case .signedOut: "Not signed in"
        case .signingIn: "Waiting for the browser…"
        case .signedIn(let name):
            if let pollError = account.pollError { "Signed in as \(name) — \(pollError)" } else { "Signed in as \(name)" }
        case .offline:
            account.userName.map { "Offline — signed in as \($0)" } ?? "Offline"
        case .error(let message): message
        }
    }

    private var statusIsProblem: Bool {
        switch account.status {
        case .offline, .error: true
        case .signedIn: account.pollError != nil
        default: false
        }
    }
}

#Preview("Signed in") {
    let account = LinearAccount(connector: FakeLinearConnector(signedIn: true), monitorNetwork: false)
    return Form { LinearAccountRow() }
        .formStyle(.grouped)
        .environment(account)
        .task { await account.start() }
}

#Preview("Signed out") {
    Form { LinearAccountRow() }
        .formStyle(.grouped)
        .environment(LinearAccount(connector: FakeLinearConnector(), monitorNetwork: false))
}
