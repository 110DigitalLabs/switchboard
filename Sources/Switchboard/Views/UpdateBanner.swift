import AppKit
import SwiftUI

/// A row at the foot of the sidebar when a newer Switchboard is out, styled
/// like the session rows above it: title with a status capsule, then a
/// secondary detail line holding the actions.
struct UpdateBanner: View {
    @Environment(AppUpdater.self) private var updater
    @Environment(\.sessionListFonts) private var fonts
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        if let release = updater.bannerRelease {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Switchboard \(release.version.description)")
                        .font(fonts.title)
                        .lineLimit(1)
                    badge
                    Spacer(minLength: 4)
                    if case .available = updater.state {
                        Button {
                            updater.skip()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Skip this version")
                    }
                }
                detail(for: release)
                    .font(fonts.detail)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch updater.state {
        case .installing: capsule("Updating", palette.yellow)
        case .installed: capsule("Ready", palette.green)
        case .failed: capsule("Failed", palette.red)
        default: capsule("Available", palette.cyan)
        }
    }

    private func capsule(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func detail(for release: Release) -> some View {
        switch updater.state {
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Installing…")
            }
        case .installed:
            HStack(spacing: 4) {
                link("Restart now") { updater.restart() }
                    .help("Quits and reopens Switchboard. Running terminals end; your rows come back.")
                Text("· or next launch")
            }
        case .failed(_, let message):
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    link("Try again") { updater.install() }
                    Text("·")
                    link("Release page") { NSWorkspace.shared.open(release.pageURL) }
                }
            }
        default:
            HStack(spacing: 4) {
                Text("You have \(updater.currentVersion?.description ?? "an older version")")
                Text("·")
                link("Update") { updater.install() }
                Text("·")
                link("What's new") { NSWorkspace.shared.open(release.pageURL) }
            }
            .lineLimit(1)
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .foregroundStyle(palette.cyan)
    }
}
