import Foundation
import GTDModel

/// The `gtd://routine/<id>` deep link `StartRoutineIntent` asks the app to open once it is
/// foregrounded (R3). The format matches `GTDNotifications.NotificationRoute`'s routine case
/// exactly (`"gtd://routine/\(id.path)"`), so T40 can parse a pending route from either source
/// with the same `NotificationRoute(url:)` call. `GTDIntents` does not depend on
/// `GTDNotifications` (ARCHITECTURE §2, frozen dependency graph), so the format is reproduced
/// here rather than shared — `RoutineDeepLinkTests` pins it to the literal
/// `GTDNotificationsTests` also assert on.
///
/// **Assumption (flag for T40):** the routine's `NoteID` is built from `VaultLayout.default`,
/// because the intent has no access to a loaded `GTDConfig` (it must not load or index the
/// vault). A vault with a customised `routines` folder gets a path that does not resolve; T40
/// should fall back to matching the routine by title when the path lookup misses.
public enum RoutineDeepLink {
    public static func url(forRoutineTitled title: String, layout: VaultLayout = .default) -> String {
        let id = NoteID(path: "\(layout.routines)/\(VaultLayout.sanitize(title)).md")
        return "gtd://routine/\(id.path)"
    }
}

/// The pending route `ProcessInboxIntent` asks the app to open (I1). Not a
/// `GTDNotifications.NotificationRoute` case today — there is no "process inbox" notification —
/// so T40 should treat this string specially (or add a matching case to `NotificationRoute`)
/// alongside the existing `gtd://` cases when consuming `PendingRoute`.
public enum InboxDeepLink {
    public static let url = "gtd://inbox"
}
