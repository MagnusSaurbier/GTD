import Foundation

/// Pure derived queries over a `VaultSnapshot` — the read half of the GTD semantics.
/// Views and backends never re-implement these.
///
/// Every query is **total and deterministic**: each sort uses a total order (a unique `NoteID`
/// is always the last tiebreaker), so the same snapshot always produces the same list.
///
/// Conversions from `Date` to `Day` take a `calendar` parameter that defaults to `.current`;
/// the reducer passes `env.calendar` so its results never depend on the machine's time zone.
///
/// Owned by **T11**.
public enum Rules {

    // MARK: - Inbox

    /// The processing queue: LIFO, newest first, excluding items deferred to the weekly
    /// review (I1, I5).
    public static func inboxQueue(_ s: VaultSnapshot) -> [InboxItem] {
        s.inbox
            .filter { $0.reviewReason == nil }
            .sorted { lhs, rhs in
                if lhs.created != rhs.created { return lhs.created > rhs.created }
                return lhs.id.path > rhs.id.path
            }
    }

    /// Items parked for the weekly review, oldest first, each with its reason (I5, §10.1).
    public static func reviewDeferredInbox(_ s: VaultSnapshot) -> [InboxItem] {
        s.inbox
            .filter { $0.reviewReason != nil }
            .sorted { lhs, rhs in
                if lhs.created != rhs.created { return lhs.created < rhs.created }
                return lhs.id.path < rhs.id.path
            }
    }

    // MARK: - Visibility

    /// D1 — a defer date hides an action from every list until the day it names.
    public static func isVisible(_ action: Action, today: Day) -> Bool {
        guard !action.status.isClosed else { return false }        // A5
        if let deferDate = action.deferDate, deferDate > today { return false }
        return true
    }

    /// Everything a list may show today: open actions whose defer date has arrived (A5, D1).
    public static func visibleActions(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions.filter { isVisible($0, today: today) }
    }

    /// Actions hidden by their defer date, soonest first (D1).
    public static func deferredList(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions
            .filter { action in
                guard !action.status.isClosed, let deferDate = action.deferDate else { return false }
                return deferDate > today
            }
            .sorted { lhs, rhs in
                let l = lhs.deferDate ?? today
                let r = rhs.deferDate ?? today
                if l != r { return l < r }
                return lhs.id.path < rhs.id.path
            }
    }

    // MARK: - Next and the cap

    /// How many actions occupy a Next slot **today** (A3; ARCHITECTURE §6: `in-progress`
    /// counts too).
    ///
    /// R-2: a Next item may carry a future `defer`. While it is hidden it is not a commitment
    /// for today, so it does not occupy a slot; on its defer date it comes back and counts
    /// again — possibly pushing Next over the cap, which is shown (`16/15`) and never repaired
    /// automatically. `checkCap` only blocks commands that make the number worse.
    public static func countsTowardCap(_ s: VaultSnapshot, today: Day) -> Int {
        s.actions.count { $0.status.countsTowardCap && isVisible($0, today: today) }
    }

    /// True when no further action fits into Next (A3, I4).
    public static func isAtCap(_ s: VaultSnapshot, today: Day) -> Bool {
        countsTowardCap(s, today: today) >= s.config.nextCap
    }

    /// The Next list (E1): `in-progress` pinned on top, then `next`, filtered by context and by
    /// the time available. Chase items are a separate section — see `chaseItems`.
    ///
    /// The list is never truncated to the cap: an over-cap vault (only reachable by editing
    /// files by hand) must stay repairable from the app, and `capSignal` shows `17/15`.
    public static func nextList(
        _ s: VaultSnapshot,
        contexts: [String] = [],
        timeAvailable: Int? = nil,
        today: Day
    ) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.status.countsTowardCap }
            .filter { matches($0, contexts: contexts) }
            .filter { fits($0, timeAvailable: timeAvailable) }
            .sorted(by: nextIsOrdered)
    }

    /// The iPhone Next list: hard-filtered to the on-the-go contexts (E2, N5).
    /// An action without any context is not on the go — undecided never means "everywhere".
    public static func onTheGoNextList(
        _ s: VaultSnapshot,
        contexts: [String] = [],
        timeAvailable: Int? = nil,
        today: Day
    ) -> [Action] {
        let allowed = Set(s.config.onTheGoContexts)
        let requested = contexts.isEmpty ? s.config.onTheGoContexts : contexts.filter { allowed.contains($0) }
        guard !requested.isEmpty else { return [] }
        return nextList(s, contexts: requested, timeAvailable: timeAvailable, today: today)
    }

    /// E1 — an action matches the context filter when it carries at least one of the chosen
    /// contexts. No filter ⇒ everything; an action without contexts never matches a filter.
    static func matches(_ action: Action, contexts: [String]) -> Bool {
        guard !contexts.isEmpty else { return true }
        return !Set(action.contexts).isDisjoint(with: Set(contexts))
    }

    /// E1 — the time filter. An undecided estimate is never filtered away (§1 "no lying defaults").
    static func fits(_ action: Action, timeAvailable: Int?) -> Bool {
        guard let timeAvailable else { return true }
        guard let bucket = action.timeBucket else { return true }
        return bucket.fits(available: timeAvailable)
    }

    /// Total order for Next (E1): `in-progress` first, then the nearest `due`, then the oldest
    /// capture, then the path — so the list never reshuffles between two identical snapshots.
    static func nextIsOrdered(_ lhs: Action, _ rhs: Action) -> Bool {
        if (lhs.status == .inProgress) != (rhs.status == .inProgress) {
            return lhs.status == .inProgress
        }
        let lhsDue = lhs.due?.serial ?? Int.max
        let rhsDue = rhs.due?.serial ?? Int.max
        if lhsDue != rhsDue { return lhsDue < rhsDue }
        let lhsCreated = lhs.created ?? .distantPast
        let rhsCreated = rhs.created ?? .distantPast
        if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
        return lhs.id.path < rhs.id.path
    }

    // MARK: - Waiting

    /// Waiting items whose follow-up date has arrived — shown above Next as "chase" (W2).
    public static func chaseItems(_ s: VaultSnapshot, today: Day) -> [Action] {
        waitingList(s, today: today).filter { action in
            guard let followUp = action.followUpDate else { return false }
            return followUp <= today
        }
    }

    /// The waiting view (W2), sorted by staleness: the longest-overdue follow-up first,
    /// then the oldest capture.
    public static func waitingList(_ s: VaultSnapshot, today: Day) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.status == .waiting }
            .sorted { lhs, rhs in
                let l = lhs.followUpDate?.serial ?? Int.max
                let r = rhs.followUpDate?.serial ?? Int.max
                if l != r { return l < r }
                let lhsCreated = lhs.created ?? .distantPast
                let rhsCreated = rhs.created ?? .distantPast
                if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
                return lhs.id.path < rhs.id.path
            }
    }

    /// W2 — how long this item has been waiting, in days. `nil` when the note has no `created`.
    public static func waitingSince(_ action: Action, today: Day, calendar: Calendar = .current) -> Int? {
        guard action.status == .waiting, let created = action.created else { return nil }
        return today.days(since: Day(created, calendar: calendar))
    }

    // MARK: - Projects

    /// P4 — the actions that actually move a project: open, visible today, and committed.
    /// `someday` is explicitly *not* a commitment, so it does not keep a project off the
    /// stalled list; a deferred action does not either, because it is hidden until its date.
    public static func openActions(of project: NoteID, in s: VaultSnapshot, today: Day) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.project == project && $0.status != .someday }
            .sorted(by: nextIsOrdered)
    }

    /// An active project with no open action is stalled (P4).
    public static func isStalled(_ project: Project, in s: VaultSnapshot, today: Day) -> Bool {
        guard project.status == .active else { return false }
        return openActions(of: project.id, in: s, today: today).isEmpty
    }

    /// Every visible action of the snapshot, bucketed by the project it belongs to.
    ///
    /// The list queries below used to ask `visibleActions` once **per project** — O(projects ×
    /// actions), which on a 1 000-action vault cost tens of milliseconds on every snapshot, for
    /// every view that shows the projects list or the stalled badge. One pass, one dictionary,
    /// same answers (T41).
    private static func visibleActionsByProject(
        _ s: VaultSnapshot, today: Day
    ) -> [NoteID: [Action]] {
        var byProject: [NoteID: [Action]] = [:]
        for action in s.actions where isVisible(action, today: today) {
            guard let project = action.project else { continue }
            byProject[project, default: []].append(action)
        }
        return byProject
    }

    /// P4 with the project's visible actions already in hand — the same rule `isStalled` and
    /// `openActions` apply: `someday` is not a commitment, and a deferred action is not now
    /// (deferred actions are not in `visible` at all).
    private static func isStalled(_ project: Project, visible: [Action]) -> Bool {
        guard project.status == .active else { return false }
        return !visible.contains { $0.status != .someday }
    }

    /// Active projects with zero open actions — badge plus weekly-review sweep (P4, §10.1).
    public static func stalledProjects(_ s: VaultSnapshot, today: Day) -> [Project] {
        let byProject = visibleActionsByProject(s, today: today)
        return s.projects
            .filter { isStalled($0, visible: byProject[$0.id] ?? []) }
            .sorted { ($0.title, $0.id.path) < ($1.title, $1.id.path) }
    }

    /// One row of the projects list (E4).
    public struct ProjectRow: Sendable, Equatable {
        public var project: Project
        /// The project's Next / in-progress actions (P4: several in parallel are allowed).
        public var activeActions: [Action]
        /// Steps that are neither done nor promoted yet (P4).
        public var remainingSteps: Int
        public var isStalled: Bool

        public init(project: Project, activeActions: [Action], remainingSteps: Int, isStalled: Bool) {
            self.project = project
            self.activeActions = activeActions
            self.remainingSteps = remainingSteps
            self.isStalled = isStalled
        }
    }

    /// Rows for the projects list (E4): active projects first, then on-hold, someday, done.
    public static func projectRows(_ s: VaultSnapshot, today: Day) -> [ProjectRow] {
        let byProject = visibleActionsByProject(s, today: today)
        return s.projects
            .map { project in
                let visible = byProject[project.id] ?? []
                return ProjectRow(
                    project: project,
                    activeActions: visible
                        .filter { $0.status.countsTowardCap }
                        .sorted(by: nextIsOrdered),
                    remainingSteps: project.openSteps.count,
                    isStalled: isStalled(project, visible: visible))
            }
            .sorted { lhs, rhs in
                let l = statusRank(lhs.project.status)
                let r = statusRank(rhs.project.status)
                if l != r { return l < r }
                if lhs.project.title != rhs.project.title { return lhs.project.title < rhs.project.title }
                return lhs.project.id.path < rhs.project.id.path
            }
    }

    private static func statusRank(_ status: ProjectStatus) -> Int {
        switch status {
        case .active: 0
        case .onHold: 1
        case .someday: 2
        case .done: 3
        }
    }

    /// A2 — an action with two or more checkboxes is probably a project. A query, not a prompt:
    /// the views show the inline "Turn into project" button when this is true.
    public static func suggestsProject(_ action: Action) -> Bool { action.checkboxes.count >= 2 }

    // MARK: - Sidebar

    /// Live counts for the Mac sidebar (E3). Every count matches the list the row opens, so
    /// deferred actions are counted only under `deferred`.
    public struct SidebarCounts: Sendable, Equatable {
        public var inbox: Int
        public var next: Int
        public var someday: Int
        public var waiting: Int
        public var projects: Int
        public var deferred: Int

        public init(inbox: Int, next: Int, someday: Int, waiting: Int, projects: Int, deferred: Int) {
            self.inbox = inbox
            self.next = next
            self.someday = someday
            self.waiting = waiting
            self.projects = projects
            self.deferred = deferred
        }
    }

    /// E3 — the sidebar's live counts.
    public static func sidebarCounts(_ s: VaultSnapshot, today: Day) -> SidebarCounts {
        let visible = visibleActions(s, today: today)
        return SidebarCounts(
            inbox: inboxQueue(s).count,
            next: visible.count { $0.status.countsTowardCap },
            someday: visible.count { $0.status == .someday },
            waiting: visible.count { $0.status == .waiting },
            projects: s.projects.count { $0.status == .active },
            deferred: deferredList(s, today: today).count)
    }

    // MARK: - Signals (STYLEGUIDE §2.2)

    /// Every signal that applies to an action, highest step first (STYLEGUIDE §2.2).
    /// `DesignSystem` renders at most two of them; the order here is stable.
    public static func signals(
        for action: Action,
        today: Day,
        policy: StalenessPolicy = .default,
        calendar: Calendar = .current
    ) -> [Signal] {
        var out: [Signal] = []

        // due within 3 days / today / passed
        if let due = action.due, !action.status.isClosed {
            let delta = due.days(since: today)
            if delta < 0 {
                out.append(Signal(kind: .overdue(days: -delta), step: .overdue))
            } else if delta == 0 {
                out.append(Signal(kind: .dueToday, step: .attention))
            } else if delta <= policy.dueSoonDays {
                out.append(Signal(kind: .dueSoon(due), step: .aging))
            }
        }

        // waiting: follow-up soon / passed ⇒ chase (W2)
        if action.status == .waiting, let followUp = action.followUpDate {
            let delta = followUp.days(since: today)
            if delta <= 0 {
                out.append(Signal(kind: .chase(days: -delta), step: .attention))
            } else if delta <= policy.followUpSoonDays {
                out.append(Signal(kind: .followUpSoon(followUp), step: .aging))
            }
        }

        // D1 — the item came back today (the badge lives for `returnedFromDeferDays` days).
        if let deferDate = action.deferDate, !action.status.isClosed,
           deferDate <= today, today.days(since: deferDate) < policy.returnedFromDeferDays {
            out.append(Signal(kind: .returnedFromDefer, step: .neutral))
        }

        // "Untouched" = file modification date (ARCHITECTURE §5); a status change rewrites the file.
        if let modified = action.modified, !action.status.isClosed {
            let days = today.days(since: Day(modified, calendar: calendar))
            if days > policy.actionAttentionDays {
                out.append(Signal(kind: .untouched(days: days), step: .attention))
            } else if days > policy.actionAgingDays {
                out.append(Signal(kind: .untouched(days: days), step: .aging))
            }
        }

        return byStep(out)
    }

    /// Inbox item older than the inbox threshold (STYLEGUIDE §2.2).
    public static func signals(
        for item: InboxItem,
        today: Day,
        policy: StalenessPolicy = .default,
        calendar: Calendar = .current
    ) -> [Signal] {
        let days = today.days(since: Day(item.created, calendar: calendar))
        guard days > policy.inboxAgingDays else { return [] }
        return [Signal(kind: .inboxAge(days: days), step: .aging)]
    }

    /// Active project with zero open actions (P4, STYLEGUIDE §2.2).
    public static func signals(for project: Project, in s: VaultSnapshot, today: Day) -> [Signal] {
        isStalled(project, in: s, today: today) ? [Signal(kind: .stalled, step: .attention)] : []
    }

    /// Highest step first; signals of the same step keep the order they were produced in.
    /// (`sorted(by:)` is not stable, so the index is part of the comparison.)
    private static func byStep(_ signals: [Signal]) -> [Signal] {
        signals.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.step != rhs.element.step { return lhs.element.step > rhs.element.step }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The `due` signal alone, for rows that show nothing else (STYLEGUIDE §2.2).
    public static func dueBadge(
        for action: Action, today: Day, policy: StalenessPolicy = .default, calendar: Calendar = .current
    ) -> Signal? {
        signals(for: action, today: today, policy: policy, calendar: calendar).first {
            switch $0.kind {
            case .overdue, .dueToday, .dueSoon: true
            default: false
            }
        }
    }

    /// The `back` badge for an item whose defer date has just arrived (D1).
    public static func returnedFromDeferBadge(
        for action: Action, today: Day, policy: StalenessPolicy = .default, calendar: Calendar = .current
    ) -> Signal? {
        signals(for: action, today: today, policy: policy, calendar: calendar).first {
            if case .returnedFromDefer = $0.kind { return true }
            return false
        }
    }

    /// Sidebar / Next-view cap signal: `15/15` at the cap, overdue styling above it (A3, §2.2).
    public static func capSignal(_ s: VaultSnapshot, today: Day) -> Signal? {
        let count = countsTowardCap(s, today: today)
        let cap = s.config.nextCap
        if count > cap { return Signal(kind: .cap(count: count, cap: cap), step: .overdue) }
        if count == cap { return Signal(kind: .cap(count: count, cap: cap), step: .attention) }
        return nil
    }

    // MARK: - Archive

    /// A5 — closed actions (done, or still carrying the legacy `status: trash`) whose closing
    /// date is older than the archive threshold. R-1 sends the legacy-trashed ones to
    /// `GTD/Trash/` rather than `Archive/` — `archiveCompleted` decides that, not this query.
    /// A hand-edited note without `completedDate` falls back to its file modification date;
    /// with neither, it is never archived (the app does not guess when something was closed).
    public static func archiveCandidates(
        _ s: VaultSnapshot,
        today: Day,
        policy: StalenessPolicy = .default,
        calendar: Calendar = .current
    ) -> [Action] {
        s.actions
            .filter { action in
                guard action.status.isClosed, let closed = closedDay(action, calendar: calendar) else {
                    return false
                }
                return today.days(since: closed) > policy.archiveAfterDays
            }
            .sorted { $0.id.path < $1.id.path }
    }

    /// A5 — the day an action was closed, used for the archive threshold and `Archive/YYYY/MM/`.
    public static func closedDay(_ action: Action, calendar: Calendar = .current) -> Day? {
        if let completed = action.completedDate { return Day(completed, calendar: calendar) }
        if let modified = action.modified { return Day(modified, calendar: calendar) }
        return nil
    }

    // MARK: - Timeline (D3)

    public enum TimelineKind: Sendable, Equatable, Hashable, CaseIterable {
        case deferred
        case due
        case followUp
    }

    /// One marker on the Mac calendar strip (D3).
    public struct TimelineEntry: Sendable, Equatable {
        public var day: Day
        public var action: NoteID
        public var title: String
        public var kind: TimelineKind

        public init(day: Day, action: NoteID, title: String, kind: TimelineKind) {
            self.day = day
            self.action = action
            self.title = title
            self.kind = kind
        }
    }

    /// Defer, due and follow-up dates of all open actions in `from...to` (D3).
    public static func timeline(_ s: VaultSnapshot, from: Day, to: Day) -> [TimelineEntry] {
        guard from <= to else { return [] }
        var out: [TimelineEntry] = []
        for action in s.actions where !action.status.isClosed {
            func add(_ day: Day?, _ kind: TimelineKind) {
                guard let day, day >= from, day <= to else { return }
                out.append(TimelineEntry(day: day, action: action.id, title: action.title, kind: kind))
            }
            add(action.deferDate, .deferred)
            add(action.due, .due)
            if action.status == .waiting { add(action.followUpDate, .followUp) }
        }
        return out.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            if lhs.action != rhs.action { return lhs.action.path < rhs.action.path }
            return kindRank(lhs.kind) < kindRank(rhs.kind)
        }
    }

    private static func kindRank(_ kind: TimelineKind) -> Int {
        switch kind {
        case .deferred: 0
        case .due: 1
        case .followUp: 2
        }
    }

    // MARK: - Undo (N6)

    /// N6 — undo covers the last **filing or status change**, i.e. everything that moves an item
    /// through the system. Settings, the routine log and the weekly review note are not undoable
    /// (they are not filings, and the routine log is per-device append-only).
    /// Both backends (`InMemoryBackend`, `GTDServices.VaultBackend`) use this one definition.
    public static func isUndoable(_ command: GTDCommand) -> Bool {
        switch command {
        case .updateConfig, .logRoutineStep, .setRoutineTime, .saveWeeklyReview, .archiveCompleted:
            false
        case .editInboxText, .fileInbox, .deferInboxToReview, .createAction, .updateAction,
             .setStatus, .trashAction, .complete, .toggleCheckbox, .convertActionToProject,
             .createArea, .createProject, .updateProject, .promoteStep:
            true
        }
    }
}
