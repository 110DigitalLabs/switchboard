import SwiftUI

/// Lists recent Claude Code and Codex conversations from the agents' own
/// history, newest first, and reopens the chosen one in a new row.
struct ResumeExistingSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var conversations: [PastConversation]?
    @State private var filter = ""
    @State private var selection: PastConversation.ID?
    @State private var confirming: PastConversation?

    private var visible: [PastConversation] {
        let owned = store.ownedConversationIDs
        let all = (conversations ?? []).filter { !owned.contains($0.conversationID) }
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.directory.localizedCaseInsensitiveContains(query)
        }
    }

    private var selected: PastConversation? {
        selection.flatMap { id in visible.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resume Existing Conversation").font(.headline)
            Text("Recent Claude Code and Codex conversations. Quit one in its other terminal before "
                 + "resuming it here, so it does not run in two places.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Filter by title or folder", text: $filter)
                .textFieldStyle(.roundedBorder)

            List(visible, selection: $selection) { conversation in
                ConversationRow(conversation: conversation)
            }
            .frame(minHeight: 320)
            .overlay { placeholder }
            .contextMenu(forSelectionType: PastConversation.ID.self) { _ in
            } primaryAction: { _ in
                choose()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resume") { choose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
        }
        .padding(16)
        .frame(width: 620)
        .task {
            conversations = await Task.detached(priority: .userInitiated) { ConversationHistory.recent() }.value
        }
        .confirmationDialog("Resume “\(confirming?.displayTitle ?? "")” here?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { conversation in
            Button("Resume Anyway") { resume(conversation) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It was active in the last two minutes and may still be open in another terminal. "
                 + "Running one conversation in two places mixes up its history.")
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if conversations == nil {
            ProgressView()
        } else if visible.isEmpty {
            Text(filter.isEmpty ? "No saved conversations found" : "No matches")
                .foregroundStyle(.secondary)
        }
    }

    private func choose() {
        guard let conversation = selected else { return }
        if conversation.isRecentlyActive() {
            confirming = conversation
        } else {
            resume(conversation)
        }
    }

    private func resume(_ conversation: PastConversation) {
        store.resume(conversation)
        dismiss()
    }
}

private struct ConversationRow: View {
    let conversation: PastConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(conversation.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if conversation.isRecentlyActive() {
                    Text("Active now")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                Text(conversation.agent.displayName)
                Text("·")
                Text((conversation.directory as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(conversation.lastActive, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help(conversation.directory)
    }
}
