import AppKit
import SwiftUI

/// A strip at the foot of the sidebar when a newer Switchboard is out.
struct UpdateBanner: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        if let release = updater.bannerRelease {
            VStack(alignment: .leading, spacing: 6) {
                content(for: release)
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private func content(for release: Release) -> some View {
        switch updater.state {
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Updating to \(release.version.description)…")
            }
        case .installed:
            Label("Switchboard \(release.version.description) is installed", systemImage: "checkmark.circle")
            HStack {
                Button("Restart Now") { updater.restart() }
                    .help("Quits and reopens Switchboard. Running terminals end; your rows come back.")
                Text("or next time you open it")
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        case .failed(_, let message):
            Label("Couldn't update to \(release.version.description)", systemImage: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try Again") { updater.install() }
                Button("Release Page") { NSWorkspace.shared.open(release.pageURL) }
            }
            .controlSize(.small)
        default:
            HStack(alignment: .firstTextBaseline) {
                Label("Switchboard \(release.version.description) is available", systemImage: "arrow.down.circle")
                Spacer(minLength: 4)
                Button {
                    updater.skip()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Skip this version")
            }
            HStack {
                Button("Update") { updater.install() }
                Button("What's New") { NSWorkspace.shared.open(release.pageURL) }
            }
            .controlSize(.small)
        }
    }
}
