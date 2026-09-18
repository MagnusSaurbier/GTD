import Foundation
import GTDModel

/// What a notification is about. Drives the identifier, so re-planning is idempotent.
public enum NotificationKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// A deferred item comes back today (D1, D2).
    case deferReturn
    /// A `due` date is approaching or has arrived.
    case dueApproaching
    /// A waiting item's follow-up is due (W1).
    case followUp
    /// A routine starts (R3) — a repeating daily trigger.
    case routineStart
    /// Several same-morning items collapsed into one ("3 items came back today").
    case summary
}

/// One pending local notification, fully described and platform-free so the planner stays pure.
public struct PlannedNotification: Sendable, Equatable, Identifiable {
    /// Stable: `<kind>:<note path>` (plus the day for non-repeating kinds).
    public let id: String
    public var kind: NotificationKind
    public var title: String
    public var body: String
    /// When it fires. Repeating kinds use the time of day only.
    public var fireDate: Date
    public var repeatsDaily: Bool
    /// `gtd://routine/<id>`, `gtd://action/<path>`, `gtd://waiting`.
    public var deepLink: String

    public init(
        id: String,
        kind: NotificationKind,
        title: String,
        body: String,
        fireDate: Date,
        repeatsDaily: Bool = false,
        deepLink: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.repeatsDaily = repeatsDaily
        self.deepLink = deepLink
    }
}

/// Device-local notification preferences — not in the vault (ARCHITECTURE §3).
public struct DeviceNotificationSettings: Sendable, Equatable, Codable {
    public var enabledKinds: Set<NotificationKind>
    /// When "morning" notifications fire.
    public var morningTime: DayTime

    public init(
        enabledKinds: Set<NotificationKind> = Set(NotificationKind.allCases),
        morningTime: DayTime = DayTime(hour: 8, minute: 0)
    ) {
        self.enabledKinds = enabledKinds
        self.morningTime = morningTime
    }

    public static let `default` = DeviceNotificationSettings()
}

/// **Owned by T13.** Pure: snapshot in, notifications out. Respects the iOS limit of 64 pending
/// requests (routines first, then soonest first; same-morning items collapse into a summary).
public enum NotificationPlanner {
    /// iOS keeps at most 64 pending requests per app.
    public static let maxPending = 64

    public static func plan(
        snapshot: VaultSnapshot,
        now: Date,
        calendar: Calendar = .current,
        settings: DeviceNotificationSettings = .default
    ) -> [PlannedNotification] {
        []   // T13
    }
}

/// Deep link carried by a notification, parsed back by the app shell (T40).
public enum NotificationRoute: Sendable, Equatable {
    case routine(NoteID)
    case action(NoteID)
    case waiting

    public init?(url: String) {
        guard let scheme = url.range(of: "gtd://") else { return nil }
        let rest = String(url[scheme.upperBound...])
        if rest == "waiting" {
            self = .waiting
        } else if rest.hasPrefix("routine/") {
            self = .routine(NoteID(path: String(rest.dropFirst("routine/".count))))
        } else if rest.hasPrefix("action/") {
            self = .action(NoteID(path: String(rest.dropFirst("action/".count))))
        } else {
            return nil
        }
    }

    public var url: String {
        switch self {
        case let .routine(id): "gtd://routine/\(id.path)"
        case let .action(id): "gtd://action/\(id.path)"
        case .waiting: "gtd://waiting"
        }
    }
}

/// Talks to `UNUserNotificationCenter` behind a protocol so the planner stays testable.
/// The real centre lives in a `#if canImport(UserNotifications)` file. **Owned by T13.**
public protocol NotificationCenterPort: Sendable {
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func remove(identifiers: [String]) async
}

/// Diffs the plan against what is pending and applies only the delta. **Owned by T13.**
public struct NotificationScheduler: Sendable {
    private let center: any NotificationCenterPort

    public init(center: any NotificationCenterPort) {
        self.center = center
    }

    public func sync(planned: [PlannedNotification]) async throws {
        let pending = Set(await center.pendingIdentifiers())
        let wanted = Set(planned.map(\.id))
        await center.remove(identifiers: Array(pending.subtracting(wanted)))
        for notification in planned where !pending.contains(notification.id) {
            try await center.add(notification)
        }
    }
}
