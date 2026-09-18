import Foundation

/// Mirrors `GTDNotifications.NotificationKind`'s cases and raw values so the notification-toggle
/// section can be built without importing `GTDNotifications` (features depend on `GTDAppCore` +
/// `DesignSystem` only, per ARCHITECTURE §2). `DeviceSettings.notificationKinds` is keyed by
/// `rawValue`. **Keep in sync if T13 adds or renames a kind** — `GTDNotificationsTests` and
/// `FeatureSettingsTests` both cover it, so a mismatch shows up as a failing test on either side.
public enum NotificationKindOption: String, CaseIterable, Sendable, Identifiable {
    case deferReturn
    case dueApproaching
    case followUp
    case routineStart
    case summary

    public var id: String { rawValue }

    /// Settings-row label. Not part of STYLEGUIDE §6.3's fixed vocabulary, so it stays a plain
    /// literal here rather than a `Copy` constant.
    public var label: String {
        switch self {
        case .deferReturn: "Deferred items"
        case .dueApproaching: "Due dates"
        case .followUp: "Follow-ups"
        case .routineStart: "Routines"
        case .summary: "Daily summary"
        }
    }
}
