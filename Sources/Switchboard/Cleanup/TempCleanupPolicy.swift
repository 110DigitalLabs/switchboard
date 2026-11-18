import Foundation

/// When kept temp and scratch rows expire. Pure.
enum TempCleanupPolicy {
    static let interval: TimeInterval = 6 * 60 * 60

    /// Kept rows closed more than `days` days before `now`.
    static func expired(_ sessions: [Session], now: Date, days: Int) -> [UUID] {
        let limit = TimeInterval(max(days, 0)) * 86_400
        return sessions.compactMap { session in
            guard let closedAt = session.closedAt, now.timeIntervalSince(closedAt) > limit else { return nil }
            return session.id
        }
    }

    /// Whole days until a kept row is deleted, rounded up, never negative.
    static func daysRemaining(closedAt: Date, now: Date, days: Int) -> Int {
        let remaining = closedAt.addingTimeInterval(TimeInterval(days) * 86_400).timeIntervalSince(now)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    static func keptNote(closedAt: Date, now: Date, days: Int) -> String {
        let n = daysRemaining(closedAt: closedAt, now: now, days: days)
        return switch n {
        case 0: "kept · deletes soon"
        case 1: "kept · deletes in 1 day"
        default: "kept · deletes in \(n) days"
        }
    }

    /// Whether closing a live row asks about deleting its folder.
    static func asksBeforeClosing(_ session: Session) -> Bool {
        session.closedAt == nil && session.kind.isBottomGrouped
    }
}
