#if canImport(UserNotifications)
import Foundation
// `UNUserNotificationCenter` is not annotated `Sendable` in the SDK, but Apple documents it as
// safe to use from any thread; `@preconcurrency` is what lets this `Sendable` struct hold it.
@preconcurrency import UserNotifications

/// The real `UNUserNotificationCenter` behind `NotificationCenterPort`. Entirely guarded by
/// `#if canImport(UserNotifications)` per ARCHITECTURE §5 — it only compiles on Apple platforms
/// and was written **blind** (no Xcode/Apple SDK in the build-out container). Verify on a Mac:
/// see "Unverified on Linux" in this target's README.
public struct SystemNotificationCenter: NotificationCenterPort {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    public init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = ["deepLink": notification.deepLink]

        let trigger: UNCalendarNotificationTrigger
        if notification.repeatsDaily {
            // Hour/minute only, so it fires every day at that time (a routine's start).
            let time = calendar.dateComponents([.hour, .minute], from: notification.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        } else {
            let date = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: notification.fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: notification.id, content: content, trigger: trigger)
        try await center.add(request)
    }

    public func remove(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
#endif
