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

/// Pure: snapshot in, notifications out. Respects the iOS limit of 64 pending
/// requests (routines first, then soonest first; same-morning items collapse into a summary).
///
/// Kinds planned, one call covers all of them (D1, D2, R3, W2):
/// - `deferReturn` — morning of `Action.deferDate`, once.
/// - `dueApproaching` — morning of `due - 1 day` **and** morning of `due` (two notifications).
/// - `followUp` — morning of `Action.followUpDate`, for `status == .waiting` only.
/// - `routineStart` — a daily-repeating trigger at `Routine.time`.
///
/// "Morning" is `settings.morningTime`; a fire date at or before `now` is dropped ("past dates
/// ignored") so a device that has not synced in a while does not resurface stale reminders.
/// `done`/`trash` actions are never planned. When two or more non-routine notifications would
/// fire at the exact same instant (several items due the same morning), they collapse into one
/// `.summary` notification instead of paging the user repeatedly — unless `.summary` itself is
/// disabled in settings, in which case they are left separate.
public enum NotificationPlanner {
    /// iOS keeps at most 64 pending requests per app.
    public static let maxPending = 64

    public static func plan(
        snapshot: VaultSnapshot,
        now: Date,
        calendar: Calendar = .current,
        settings: DeviceNotificationSettings = .default
    ) -> [PlannedNotification] {
        var routineNotifications: [PlannedNotification] = []
        if settings.enabledKinds.contains(.routineStart) {
            for routine in snapshot.routines {
                if let notification = routineNotification(routine, now: now, calendar: calendar) {
                    routineNotifications.append(notification)
                }
            }
        }

        var candidates: [PlannedNotification] = []
        for action in snapshot.actions {
            guard !action.status.isClosed else { continue }   // A5: done and legacy trash (R-1)

            if settings.enabledKinds.contains(.deferReturn), let deferDate = action.deferDate,
               let notification = itemNotification(
                   action, day: deferDate, kind: .deferReturn,
                   title: "Back today", body: "\(action.title) is back.",
                   settings: settings, now: now, calendar: calendar) {
                candidates.append(notification)
            }

            if settings.enabledKinds.contains(.dueApproaching), let due = action.due {
                if let notification = itemNotification(
                    action, day: due.adding(days: -1), kind: .dueApproaching,
                    title: "Due tomorrow", body: "\(action.title) is due tomorrow.",
                    settings: settings, now: now, calendar: calendar) {
                    candidates.append(notification)
                }
                if let notification = itemNotification(
                    action, day: due, kind: .dueApproaching,
                    title: "Due today", body: "\(action.title) is due today.",
                    settings: settings, now: now, calendar: calendar) {
                    candidates.append(notification)
                }
            }

            if settings.enabledKinds.contains(.followUp), action.status == .waiting,
               let followUp = action.followUpDate {
                let who = action.waitingFor.map { " with \($0)" } ?? ""
                if let notification = itemNotification(
                    action, day: followUp, kind: .followUp,
                    title: "Follow up", body: "Follow up\(who) about \(action.title).",
                    settings: settings, now: now, calendar: calendar) {
                    candidates.append(notification)
                }
            }
        }

        let collapsed = settings.enabledKinds.contains(.summary)
            ? collapseSameMorning(candidates, calendar: calendar)
            : candidates

        let orderedRoutines = routineNotifications.sorted(by: chronological)
        let orderedRest = collapsed.sorted(by: chronological)
        // Cap ordering: routines first (there are only ever a handful of them and missing a
        // routine start is worse than missing a due-date ping), then soonest first.
        return Array((orderedRoutines + orderedRest).prefix(maxPending))
    }

    // MARK: - Building blocks

    /// Deterministic total order: soonest first, ties (only possible between different kinds
    /// that happen to land on the exact same instant, which collapsing already prevents for
    /// same-morning items) broken by id so the result never depends on iteration order.
    private static func chronological(_ a: PlannedNotification, _ b: PlannedNotification) -> Bool {
        a.fireDate == b.fireDate ? a.id < b.id : a.fireDate < b.fireDate
    }

    private static func routineNotification(
        _ routine: Routine, now: Date, calendar: Calendar
    ) -> PlannedNotification? {
        guard let time = routine.time else { return nil }
        guard let fireDate = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: now)
        else { return nil }
        return PlannedNotification(
            id: "\(NotificationKind.routineStart.rawValue):\(routine.id.path)",
            kind: .routineStart,
            title: routine.title,
            body: "Time for \(routine.title).",
            fireDate: fireDate,
            repeatsDaily: true,
            deepLink: NotificationRoute.routine(routine.id).url)
    }

    /// One item-bound (non-repeating) notification, or `nil` if it would fire in the past.
    private static func itemNotification(
        _ action: Action, day: Day, kind: NotificationKind,
        title: String, body: String,
        settings: DeviceNotificationSettings, now: Date, calendar: Calendar
    ) -> PlannedNotification? {
        guard let fireDate = day.date(at: settings.morningTime, in: calendar), fireDate > now
        else { return nil }
        return PlannedNotification(
            id: "\(kind.rawValue):\(action.id.path):\(day.iso)",
            kind: kind,
            title: title,
            body: body,
            fireDate: fireDate,
            repeatsDaily: false,
            deepLink: NotificationRoute.action(action.id).url)
    }

    /// Merges non-routine notifications that share an exact fire date into one `.summary`.
    private static func collapseSameMorning(
        _ notifications: [PlannedNotification], calendar: Calendar
    ) -> [PlannedNotification] {
        let grouped = Dictionary(grouping: notifications, by: \.fireDate)
        return grouped.map { fireDate, group in
            guard group.count > 1 else { return group[0] }
            let day = Day(fireDate, calendar: calendar)
            let kinds = Set(group.map(\.kind))
            let body: String
            if kinds == [.deferReturn] {
                body = "\(group.count) items came back today."
            } else if kinds == [.dueApproaching] {
                body = "\(group.count) items due soon."
            } else if kinds == [.followUp] {
                body = "\(group.count) follow-ups due today."
            } else {
                body = "\(group.count) items need your attention today."
            }
            return PlannedNotification(
                id: "\(NotificationKind.summary.rawValue):\(day.iso)",
                kind: .summary,
                title: "\(group.count) items",
                body: body,
                fireDate: fireDate,
                repeatsDaily: false,
                deepLink: "")
        }
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
/// The real centre lives in a `#if canImport(UserNotifications)` file.
public protocol NotificationCenterPort: Sendable {
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func remove(identifiers: [String]) async
}

/// Diffs the plan against what is pending and applies only the delta.
public struct NotificationScheduler: Sendable {
    private let center: any NotificationCenterPort

    public init(center: any NotificationCenterPort) {
        self.center = center
    }

    /// Asks the user for permission. Call once, e.g. the first time the user enables a
    /// notification kind in Settings; `sync(planned:)` does not request it implicitly, since a
    /// pre-authorization plan/diff must stay possible without prompting.
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization()
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
