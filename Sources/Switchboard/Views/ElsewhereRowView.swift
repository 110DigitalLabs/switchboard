import SwiftUI

/// A conversation running in another terminal, in the Running Elsewhere
/// section.
struct ElsewhereRowView: View {
    let conversation: PastConversation
    @Environment(\.sessionListFonts) private var fonts
    @Environment(\.terminalPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(conversation.displayTitle)
                    .font(fonts.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if conversation.isRecentlyActive() {
                    Text("Working")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(palette.yellow.opacity(0.2), in: Capsule())
                        .foregroundStyle(palette.yellow)
                }
            }
            HStack(spacing: 4) {
                Text(conversation.agent.displayName)
                Text("·")
                Text(URL(fileURLWithPath: conversation.directory).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(fonts.detail)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help("\(conversation.directory)\nClick to resume it here")
    }
}
