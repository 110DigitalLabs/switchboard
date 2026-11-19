import SwiftUI

/// A capsule at the bottom of the window while listening, showing the words
/// heard so far, or why listening couldn't start.
struct VoiceIndicator: View {
    let input: VoiceInput

    var body: some View {
        Group {
            switch input.state {
            case .idle:
                EmptyView()
            case .listening(let partial):
                capsule {
                    Image(systemName: "mic.fill").foregroundStyle(.red).symbolEffect(.pulse)
                    Text(partial.isEmpty ? "Listening… ⌘⇧Space to stop" : partial)
                        .foregroundStyle(partial.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
            case .failed(let message):
                capsule {
                    Image(systemName: "mic.slash.fill").foregroundStyle(.secondary)
                    Text(message)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: input.state)
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .frame(maxWidth: 560)
            .padding(.bottom, 36)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
    }
}
