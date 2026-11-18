import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store

    private var idealSidebarWidth: CGFloat {
        ((NSScreen.main?.visibleFrame.width ?? 1440) / 3).rounded()
    }

    var body: some View {
        @Bindable var store = store
        HSplitView {
            SidebarView()
                .frame(minWidth: 260, idealWidth: idealSidebarWidth, maxWidth: .infinity)
            TerminalPane()
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(minWidth: 800, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let id = store.selectedID { store.markViewed(id) }
        }
        .sheet(isPresented: $store.isPickerPresented) {
            NewSessionSheet()
        }
        .alert("Switchboard", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
