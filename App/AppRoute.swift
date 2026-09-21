import Foundation
import GTDModel
import GTDIntents
import GTDNotifications

/// Everywhere something outside the app can send it: a notification tap, a `gtd://` URL from
/// `onOpenURL`, or a `PendingRoute` an App Intent left behind (T30).
///
/// `GTDNotifications.NotificationRoute` covers three of the four; `gtd://inbox`
/// (`GTDIntents.InboxDeepLink`, from `ProcessInboxIntent`) is not one of its cases, so it is
/// matched here — one parser for every source, as T30's gotcha #2 asks for.
enum AppRoute: Equatable, Sendable {
    /// Start an inbox-processing session (I1).
    case processInbox
    /// Open one action's detail.
    case action(NoteID)
    /// Run one routine (R3).
    case routine(NoteID)
    /// Show the waiting-for list (W2).
    case waiting

    init?(url: String) {
        if url == InboxDeepLink.url {
            self = .processInbox
            return
        }
        switch NotificationRoute(url: url) {
        case let .action(id): self = .action(id)
        case let .routine(id): self = .routine(id)
        case .waiting: self = .waiting
        case nil: return nil
        }
    }

    init?(url: URL) {
        self.init(url: url.absoluteString)
    }

    /// The routine this route points at, as the vault actually holds it.
    ///
    /// `RoutineDeepLink` builds its path from `VaultLayout.default`, because an App Intent must
    /// not load the config (T30 gotcha #3), and a notification's link was built from whatever
    /// layout the planning device had. So the path is tried first and the routine's **title** is
    /// the fallback — the id in the link always ends in the routine's file name.
    static func resolveRoutine(_ id: NoteID, in snapshot: VaultSnapshot) -> Routine? {
        if let exact = snapshot.routines.first(where: { $0.id == id }) { return exact }
        let wanted = id.title
        return snapshot.routines.first { $0.id.title == wanted }
            ?? snapshot.routines.first { $0.title == wanted }
    }
}

/// A `NoteID` a SwiftUI `sheet(item:)` / `fullScreenCover(item:)` can key on.
struct NoteTarget: Identifiable, Equatable, Hashable {
    var note: NoteID
    var id: String { note.path }

    init(_ note: NoteID) {
        self.note = note
    }
}
