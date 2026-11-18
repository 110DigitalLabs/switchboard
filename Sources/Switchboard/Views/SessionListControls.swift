import SwiftUI

/// Compact sort and group menus above the session list.
struct SessionListControls: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 12) {
            Menu {
                Picker("Sort by", selection: $settings.sessionSort) {
                    ForEach(SessionSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort: \(settings.sessionSort.label)", systemImage: "arrow.up.arrow.down")
            }
            Menu {
                Picker("Group by", selection: $settings.sessionGrouping) {
                    ForEach(SessionGrouping.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Group: \(settings.sessionGrouping.label)", systemImage: "square.stack")
            }
            Spacer()
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
