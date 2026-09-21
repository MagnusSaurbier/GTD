import Foundation
import Observation
import GTDModel
import GTDNotifications
import FeatureSettings

#if canImport(UserNotifications)
import UserNotifications
#endif

/// Keeps the pending local notifications in step with the vault (D1, D2, R3, W2).
///
/// A device only knows what has synced into *its* snapshot, so the plan is rebuilt on **every**
/// snapshot change (debounced), on every foreground and in the background-refresh task — not
/// once at launch (T13's known limitation).
///
/// Taps come back as a `gtd://` deep link in the notification's `userInfo`; the delegate hands
/// them to the same `AppRouter.apply(url:)` that `onOpenURL` and `PendingRoute` use.
@MainActor
@Observable
final class NotificationService {

    /// How long a burst of snapshot changes is coalesced before re-planning. A filing session
    /// produces one command per card; re-planning after each would be pure churn.
    static let debounce: Duration = .seconds(2)

    private(set) var isAuthorized = false
    private var replan: Task<Void, Never>?

    #if canImport(UserNotifications)
    private let scheduler = NotificationScheduler(center: SystemNotificationCenter())
    private let center = UNUserNotificationCenter.current()
    private var delegate: NotificationDelegate?
    #endif

    init() {}

    /// Routes a notification tap. Set once by the shell.
    func installDelegate(_ handler: @escaping @MainActor (String) -> Void) {
        #if canImport(UserNotifications)
        let delegate = NotificationDelegate(handler: handler)
        self.delegate = delegate
        center.delegate = delegate
        #endif
    }

    /// Asked once, after onboarding — never on a cold first frame (P5/A2 presentation rule:
    /// a permission prompt is a decision, so it comes with the context that explains it).
    /// Already-decided is left alone: this never re-prompts.
    func requestAuthorizationIfNeeded() async {
        #if canImport(UserNotifications)
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .notDetermined:
            isAuthorized = (try? await scheduler.requestAuthorization()) ?? false
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
        #endif
    }

    /// Re-plans after `debounce`, replacing a pending re-plan. Call it on every snapshot change.
    func scheduleReplan(snapshot: VaultSnapshot, settings: DeviceSettings) {
        replan?.cancel()
        replan = Task { [weak self] in
            try? await Task.sleep(for: NotificationService.debounce)
            guard !Task.isCancelled else { return }
            await self?.replanNow(snapshot: snapshot, settings: settings)
        }
    }

    /// Re-plans immediately (foreground, background refresh, a settings change).
    func replanNow(snapshot: VaultSnapshot, settings: DeviceSettings) async {
        #if canImport(UserNotifications)
        replan?.cancel()
        replan = nil
        guard isAuthorized else { return }
        let planned = NotificationPlanner.plan(
            snapshot: snapshot,
            now: Date(),
            calendar: .current,
            settings: NotificationService.settings(from: settings))
        try? await scheduler.sync(planned: planned)
        #endif
    }

    /// `DeviceSettings` (what the settings screen writes, keyed by raw value) →
    /// `DeviceNotificationSettings` (what the planner takes). A kind with no stored answer is on,
    /// which is what the toggles in `FeatureSettings.SettingsView` show.
    static func settings(from device: DeviceSettings) -> DeviceNotificationSettings {
        var kinds: Set<NotificationKind> = []
        for kind in NotificationKind.allCases where device.notificationKinds[kind.rawValue] ?? true {
            kinds.insert(kind)
        }
        return DeviceNotificationSettings(enabledKinds: kinds, morningTime: device.morningTime)
    }
}

#if canImport(UserNotifications)
/// Foreground presentation + tap routing. A tapped notification carries its `gtd://` link in
/// `userInfo["deepLink"]` (`SystemNotificationCenter` puts it there).
///
/// `@unchecked Sendable`: the only stored property is an immutable closure that is isolated to
/// the main actor, and there is no mutable state at all — `UNUserNotificationCenter` may call the
/// two methods below from any queue, and both of them hop to the main actor before touching it.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let handler: @MainActor (String) -> Void

    init(handler: @escaping @MainActor (String) -> Void) {
        self.handler = handler
    }

    /// The hop, as a method rather than a closure: a `@MainActor` closure captured into a
    /// `@Sendable` one is exactly the kind of capture Swift 6 refuses.
    @MainActor private func deliver(_ link: String) {
        handler(link)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo["deepLink"] as? String
        guard let link, !link.isEmpty else { return }
        await deliver(link)
    }
}
#endif
