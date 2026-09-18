import Foundation
import GTDModel

/// Device-local settings — never in the vault (ARCHITECTURE §3). Persisted by the app shell.
/// Owned by T26.
public struct DeviceSettings: Codable, Equatable, Sendable {
    /// Notification kinds the user left on. Keys match `GTDNotifications.NotificationKind`
    /// raw values; `FeatureSettings` must not import `GTDNotifications`.
    public var notificationKinds: [String: Bool]
    /// When "morning" notifications fire.
    public var morningTime: DayTime
    /// Last knowledge folder used in inbox processing — shown as a *suggested* row (I4).
    public var lastKnowledgeFolder: String?
    /// Filters the Next view remembers per device (E1).
    public var nextContextFilter: [String]
    public var nextTimeFilter: Int?

    public init(
        notificationKinds: [String: Bool] = [:],
        morningTime: DayTime = DayTime(hour: 8, minute: 0),
        lastKnowledgeFolder: String? = nil,
        nextContextFilter: [String] = [],
        nextTimeFilter: Int? = nil
    ) {
        self.notificationKinds = notificationKinds
        self.morningTime = morningTime
        self.lastKnowledgeFolder = lastKnowledgeFolder
        self.nextContextFilter = nextContextFilter
        self.nextTimeFilter = nextTimeFilter
    }

    public static let `default` = DeviceSettings()
}
