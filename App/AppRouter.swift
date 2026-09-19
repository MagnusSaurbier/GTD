import Foundation
import Observation
import GTDModel
import GTDAppCore
import GTDIntents
import FeatureOverview

/// The iPhone's three tabs (N5, STYLEGUIDE §4.2).
enum AppTab: Hashable, CaseIterable {
    case next
    case inbox
    case routines
}

/// Where the app is looking, on both platforms, plus the flows the shell presents over it.
///
/// The Mac window's own selection lives in `FeatureOverview.OverviewNavigation`; this object owns
/// the one instance of it, so `OverviewView(navigation:)` and `OverviewCommands(navigation:)`
/// share it (T25's note to T40).
@MainActor
@Observable
final class AppRouter {
    // iPhone
    var tab: AppTab = .next
    /// Pushed action details in the Next tab.
    var nextPath: [NoteID] = []

    // Mac
    let overview = OverviewNavigation()

    // Flows the shell presents on both platforms
    /// Inbox processing (I1) — full-screen on iPhone, a sheet on Mac.
    var isProcessingInbox = false
    /// A routine opened from a notification, an intent or the routines list.
    var routineRun: NoteTarget?
    /// The weekly review (§10) — Mac only; the sidebar section is the usual way in.
    var isReviewPresented = false
    /// The quick-capture field (I7).
    var isCapturePresented = false
    /// Settings — a sheet on iPhone (the gear on Next); a `Settings` scene on Mac.
    var isSettingsPresented = false
    /// The vault-issue list (N3 §7.5) — the sidebar opens it on Mac, the gear screen on iPhone.
    var isIssuesPresented = false

    /// True while any full-screen flow is up, so the shell does not stack chrome on top of it.
    var isFlowPresented: Bool {
        isProcessingInbox || routineRun != nil || isReviewPresented || isCapturePresented
    }

    // MARK: - Routing

    /// Applies one route. `snapshot` is needed to resolve a routine link that was built from a
    /// different vault layout (T30 gotcha #3).
    func apply(_ route: AppRoute, snapshot: VaultSnapshot) {
        switch route {
        case .processInbox:
            tab = .inbox
            overview.select(.inbox)
            isProcessingInbox = true
        case let .action(id):
            guard snapshot.action(id) != nil else { return }
            tab = .next
            if nextPath.last != id { nextPath.append(id) }
            overview.open(action: id)
        case let .routine(id):
            guard let routine = AppRoute.resolveRoutine(id, in: snapshot) else { return }
            tab = .routines
            overview.select(.routines)
            routineRun = NoteTarget(routine.id)
        case .waiting:
            // The iPhone has no waiting tab (N5: reduced device) — its chase items live in Next.
            tab = .next
            overview.select(.waiting)
        }
    }

    /// A `gtd://` URL from `onOpenURL`, a notification tap or a pending intent route.
    @discardableResult
    func apply(url: String, snapshot: VaultSnapshot) -> Bool {
        guard let route = AppRoute(url: url) else { return false }
        apply(route, snapshot: snapshot)
        return true
    }

    /// Consumes what an App Intent left behind (`StartRoutineIntent`, `ProcessInboxIntent`).
    /// Called at launch and on every foreground — `consume()` clears as it reads, so a route is
    /// never delivered twice (T30).
    func consumePendingRoute(_ pending: PendingRoute, snapshot: VaultSnapshot) {
        guard let url = pending.consume() else { return }
        apply(url: url, snapshot: snapshot)
    }

    /// Consumes one snapshot update: **first** follow the notes it renamed, **then** drop what
    /// still points at notes the vault no longer has.
    ///
    /// The order is the whole point. A note's id is its file name (A1), so a rename makes the
    /// old id vanish from the snapshot exactly as a deletion does; pruning against the snapshot
    /// alone popped the detail of the very action whose title was being edited. The renames
    /// travel *with* the snapshot that produced them (`GTDAppCore.SnapshotUpdate` →
    /// `AppModel.renames`), so there is no window in which this runs with one and not the
    /// other. The two rules themselves live in `GTDAppCore.NavigationRemap`, where they are
    /// unit-tested on Linux.
    func apply(snapshot: VaultSnapshot, renames: RenameMap = .empty) {
        nextPath = NavigationRemap.path(nextPath, renames: renames, in: snapshot)
        routineRun = NavigationRemap
            .selection(routineRun?.note, renames: renames) { id in
                snapshot.routines.contains { $0.id == id }
            }
            .map { NoteTarget($0) }
        overview.apply(snapshot: snapshot, renames: renames)
    }
}
