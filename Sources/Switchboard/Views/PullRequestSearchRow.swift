import SwiftUI

/// The search result for a pasted PR URL: start a review session.
struct PullRequestSearchRow: View {
    @Environment(GitHubAccount.self) private var github
    let ref: PullRequestReference
    let actions: TicketActions
    @State private var pullRequest: PullRequest?
    @State private var isStarting = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: pullRequest?.displayState.symbolName ?? "arrow.triangle.pull")
                .foregroundStyle(pullRequest?.displayState.tint ?? .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(ref.repo.slug)#\(ref.number)").font(.callout.monospaced())
                if let pullRequest {
                    Text(pullRequest.title).foregroundStyle(.secondary).lineLimit(1)
                } else if !github.isAvailable {
                    Text("GitHub unavailable: the session starts without PR details.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if isStarting {
                ProgressView().controlSize(.small)
            } else {
                Button("Review") {
                    isStarting = true
                    Task {
                        await actions.startReview(ref, pullRequest: pullRequest)
                        isStarting = false
                    }
                }
                .help("Start a review session (no checkout) and type the PR link into it")
            }
        }
        .task(id: ref) {
            pullRequest = nil
            guard github.isAvailable else { return }
            pullRequest = try? await github.service.pullRequest(ref)
        }
    }
}
