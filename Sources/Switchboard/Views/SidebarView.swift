import SwiftUI

struct SidebarView: View {
    var body: some View {
        VStack(spacing: 0) {
            SearchHeaderView()
                .padding(10)
            SessionListControls()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Divider()
            SessionListView()
        }
    }
}
