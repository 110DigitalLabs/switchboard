import AppKit
import UserNotifications

/// Posts "finished" / "needs input" notifications and routes clicks back to
/// the row. Works without permission too: posting is skipped silently and the
/// row badge still shows.
@MainActor
final class Notifier {
    nonisolated private static let rowIDKey = "rowID"

    private let center = UNUserNotificationCenter.current()
    private let delegate: Delegate
    private var isAuthorized = false

    init(onOpenRow: @escaping @MainActor @Sendable (UUID) -> Void) {
        delegate = Delegate(onOpenRow: onOpenRow)
        center.delegate = delegate
    }

    func requestAuthorization() {
        Task {
            // Ad-hoc signed builds may be refused; that only disables banners.
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func post(title: String, body: String, rowID: UUID) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [Self.rowIDKey: rowID.uuidString]
        // One notification per row: a newer event replaces the older one.
        let request = UNNotificationRequest(identifier: rowID.uuidString, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    func clear(rowID: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [rowID.uuidString])
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
        private let onOpenRow: @MainActor @Sendable (UUID) -> Void

        init(onOpenRow: @escaping @MainActor @Sendable (UUID) -> Void) {
            self.onOpenRow = onOpenRow
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let info = response.notification.request.content.userInfo
            guard let raw = info[Notifier.rowIDKey] as? String, let id = UUID(uuidString: raw) else { return }
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
                onOpenRow(id)
            }
        }
    }
}
