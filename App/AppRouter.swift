import Foundation
import Observation
import GTDModel
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

    /// Drops navigation state that points at notes the vault no longer has.
    func prune(against snapshot: VaultSnapshot) {
        nextPath.removeAll { snapshot.action($0) == nil }
        if let target = routineRun, !snapshot.routines.contains(where: { $0.id == target.note }) {
            routineRun = nil
        }
        overview.prune(against: snapshot)
    }
}
