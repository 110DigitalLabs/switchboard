import SwiftUI

struct SidebarView: View {
    var body: some View {
        VStack(spacing: 0) {
            SearchHeaderView()
                .padding(10)
            Divider()
            SessionListView()
        }
    }
}
