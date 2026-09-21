import Foundation
import GTDModel
import GTDAppCore

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
    /// A friendly label for the picked vault folder (e.g. its last path component), set by the
    /// app shell once the security-scoped bookmark resolves. `FeatureSettings` shows this in
    /// place of the real path — it never resolves `VaultBookmark` itself (must not import
    /// `GTDVault`).
    public var vaultDisplayName: String?
    /// Mac key rebinds (R-10, N7) — `KeyBindings.defaults` until the user changes one in
    /// Settings › Keyboard (T13). `FeatureInbox.KeyMap` and `FeatureReview.ReviewSession` resolve
    /// keys through the value the app shell loads here, not through this type.
    public var keyBindings: KeyBindings

    public init(
        notificationKinds: [String: Bool] = [:],
        morningTime: DayTime = DayTime(hour: 8, minute: 0),
        lastKnowledgeFolder: String? = nil,
        nextContextFilter: [String] = [],
        nextTimeFilter: Int? = nil,
        vaultDisplayName: String? = nil,
        keyBindings: KeyBindings = .defaults
    ) {
        self.notificationKinds = notificationKinds
        self.morningTime = morningTime
        self.lastKnowledgeFolder = lastKnowledgeFolder
        self.nextContextFilter = nextContextFilter
        self.nextTimeFilter = nextTimeFilter
        self.vaultDisplayName = vaultDisplayName
        self.keyBindings = keyBindings
    }

    public static let `default` = DeviceSettings()
}
