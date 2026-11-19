import SwiftUI

/// The Tickets | Folders switch and the sort menu above the session list.
struct SessionListControls: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.sessionListFonts) private var fonts

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 8) {
            Picker("Show", selection: $settings.sessionGrouping) {
                ForEach(SessionGrouping.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Menu {
                Picker("Sort by", selection: $settings.sessionSort) {
                    ForEach(SessionSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort: \(settings.sessionSort.label)")
        }
        .font(fonts.detail)
        .foregroundStyle(.secondary)
    }
}
