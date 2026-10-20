import Foundation
import SwiftData
import UserNotifications

enum NotificationSettings {
    static let enabledKey = "stockNotificationsEnabled"
}

/// Local, on-device reminders for the stock queue (storyboard panel 7):
/// one when a fruit moves to the front (ready) and one when it passes its estimate.
/// Times follow the test clock, so jumping days ahead in the app also moves the reminders.
@MainActor
enum StockNotifier {
    private static let prefix = "stock-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces all stock reminders with ones that match the current queue.
    static func reschedule(context: ModelContext, offsetDays: Double, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }

        let items = (try? context.fetch(FetchDescriptor<StockItem>())) ?? []
        let now = TestClock.now(offsetDays: offsetDays)
        for item in items {
            guard let entry = item.entry() else { continue }
            let name = "\(entry.fruit.emoji) \(entry.fruit.displayName)"
            if entry.status(at: now) == .waiting {
                await schedule(id: "\(prefix)\(entry.id)-ready", after: entry.daysUntilReady(at: now),
                               title: "\(name) siap dikonsumsi",
                               body: "\(entry.fruit.displayName) kini berada di urutan depan stok Anda.")
            }
            if entry.status(at: now) != .overdue {
                await schedule(id: "\(prefix)\(entry.id)-overdue", after: entry.daysLeft(at: now),
                               title: "Periksa \(name)",
                               body: "\(entry.fruit.displayName) telah melewati perkiraan waktu konsumsi. Periksa kondisinya terlebih dahulu.")
            }
        }
    }

    /// Test helper: a sample reminder in 5 seconds.
    static func sendTest() async {
        await schedule(id: "\(prefix)test", afterSeconds: 5, title: "🍌 Pisang siap dikonsumsi",
                       body: "Contoh notifikasi pengujian.")
    }

    private static func schedule(id: String, after days: Double, title: String, body: String) async {
        await schedule(id: id, afterSeconds: days * 86_400, title: title, body: body)
    }

    private static func schedule(id: String, afterSeconds seconds: Double, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Shows reminders as banners even while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
