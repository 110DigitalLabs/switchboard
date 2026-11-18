import Foundation

extension SessionStore {
    /// Selects the session at a 1-based position in the visible order.
    @discardableResult
    func selectVisible(position: Int) -> UUID? {
        let order = layout.visibleOrder
        guard position >= 1, position <= order.count else { return nil }
        selectedID = order[position - 1]
        return selectedID
    }

    /// Moves the selection by `offset` in the visible order, stopping at the
    /// ends. With nothing (visible) selected, goes to the first or last row.
    @discardableResult
    func selectAdjacent(_ offset: Int) -> UUID? {
        let order = layout.visibleOrder
        guard !order.isEmpty else { return nil }
        if let current = selectedID, let index = order.firstIndex(of: current) {
            selectedID = order[min(max(index + offset, 0), order.count - 1)]
        } else {
            selectedID = offset >= 0 ? order.first : order.last
        }
        return selectedID
    }

    func isCollapsed(_ key: String) -> Bool { collapsedGroups.contains(key) }

    func setCollapsed(_ key: String, _ collapsed: Bool) {
        if collapsed { collapsedGroups.insert(key) } else { collapsedGroups.remove(key) }
    }
}
