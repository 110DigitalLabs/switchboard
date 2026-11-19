import SwiftUI

/// One icon per linked PR: open, draft, closed, or a purple merged icon.
/// Clicking opens the PR; the tooltip is "#123 title".
struct PRIconsView: View {
    @Environment(GitHubAccount.self) private var github
    let urls: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(urls, id: \.self) { url in
                PRIcon(url: url, pullRequest: github.pullRequest(for: url), isAvailable: github.isAvailable)
            }
        }
    }
}

private struct PRIcon: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.terminalPalette) private var palette
    let url: String
    let pullRequest: PullRequest?
    let isAvailable: Bool

    private var state: PullRequestDisplayState { pullRequest?.displayState ?? .unknown }

    var body: some View {
        Button {
            if let link = URL(string: url) { openURL(link) }
        } label: {
            Image(systemName: state.symbolName)
                .foregroundStyle(isAvailable ? state.tint(palette) : palette.dim)
                .opacity(isAvailable ? 1 : 0.6)
        }
        .buttonStyle(.borderless)
        .help(tooltip)
        .accessibilityLabel("\(state.accessibilityName) pull request \(tooltip)")
    }

    private var tooltip: String {
        if let pullRequest { return pullRequest.label }
        let number = PullRequestReference(url: url).map { "#\($0.number)" } ?? url
        return isAvailable ? number : "\(number) (GitHub unavailable)"
    }
}

extension PullRequestDisplayState {
    func tint(_ palette: TerminalPalette) -> Color {
        switch self {
        case .open: palette.green
        case .draft, .unknown: palette.dim
        case .closed: palette.red
        case .merged: palette.magenta
        }
    }
}
