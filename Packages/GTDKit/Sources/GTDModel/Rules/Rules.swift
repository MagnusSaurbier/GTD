import Foundation

/// Pure derived queries over a `VaultSnapshot`. Views and backends never re-implement these.
///
/// Owned by **T11** from Wave 1 on; T00 wrote straightforward implementations so the feature
/// targets have something real to render. Places that knowingly cut a corner are marked `// T11:`.
public enum Rules {

    // MARK: - Inbox

    /// The processing queue: LIFO, newest first, excluding items deferred to the weekly review (I1, I5).
    public static func inboxQueue(_ s: VaultSnapshot) -> [InboxItem] {
        s.inbox.filter { $0.reviewReason == nil }
            .sorted { ($0.created, $0.id.path) > ($1.created, $1.id.path) }
    }

    /// Items parked for the weekly review, oldest first, each with its reason (I5, §10.1).
    public static func reviewDeferredInbox(_ s: VaultSnapshot) -> [InboxItem] {
        s.inbox.filter { $0.reviewReason != nil }
            .sorted { ($0.created, $0.id.path) < ($1.created, $1.id.path) }
    }

    // MARK: - Visibility

    /// Everything a list may show today: open actions whose defer date has arrived (D1).
    public static func visibleActions(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions.filter { action in
            guard !action.status.isClosed else { return false }
            if let deferDate = action.deferDate, deferDate > today { return false }
            return true
        }
    }

    /// Actions hidden by their defer date, soonest first (D1).
    public static func deferredList(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions
            .filter { !$0.status.isClosed && ($0.deferDate.map { $0 > today } ?? false) }
            .sorted { ($0.deferDate ?? today, $0.title) < ($1.deferDate ?? today, $1.title) }
    }

    // MARK: - Next

    /// How many actions occupy a Next slot right now (A3, ARCHITECTURE §6: `in-progress` counts).
    public static func countsTowardCap(_ s: VaultSnapshot) -> Int {
        s.actions.count { $0.status.countsTowardCap }
    }

    public static func isAtCap(_ s: VaultSnapshot) -> Bool {
        countsTowardCap(s) >= s.config.nextCap
    }

    /// The Next list (E1): `in-progress` pinned on top, then `next`, filtered by context and by
    /// the time the user has available. Chase items are a separate section — see `chaseItems`.
    public static func nextList(
        _ s: VaultSnapshot,
        contexts: [String] = [],
        timeAvailable: Int? = nil,
        today: Day
    ) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.status.countsTowardCap }
            .filter { action in
                guard !contexts.isEmpty else { return true }
                return !Set(action.contexts).isDisjoint(with: Set(contexts))
            }
            .filter { action in
                guard let timeAvailable else { return true }
                // Undecided estimates are never filtered away (§1 "no lying defaults").
                guard let bucket = action.timeBucket else { return true }
                return bucket.fits(available: timeAvailable)
            }
            .sorted { lhs, rhs in
                if (lhs.status == .inProgress) != (rhs.status == .inProgress) {
                    return lhs.status == .inProgress
                }
                return sortKey(lhs) < sortKey(rhs)
            }
    }

    /// The iPhone Next list: hard-filtered to the on-the-go contexts (E2, N5).
    public static func onTheGoNextList(
        _ s: VaultSnapshot,
        contexts: [String] = [],
        timeAvailable: Int? = nil,
        today: Day
    ) -> [Action] {
        let allowed = Set(s.config.onTheGoContexts)
        let requested = contexts.isEmpty ? Array(allowed) : contexts.filter { allowed.contains($0) }
        return nextList(s, contexts: requested, timeAvailable: timeAvailable, today: today)
            .filter { !Set($0.contexts).isDisjoint(with: allowed) }
    }

    /// Waiting items whose follow-up date has arrived — shown above Next as "chase" (W2).
    public static func chaseItems(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions
            .filter { $0.status == .waiting && ($0.followUpDate.map { $0 <= today } ?? false) }
            .sorted { ($0.followUpDate ?? today, $0.title) < ($1.followUpDate ?? today, $1.title) }
    }

    /// The waiting view (W2), sorted by staleness: longest overdue follow-up first.
    public static func waitingList(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions
            .filter { $0.status == .waiting }
            .sorted { lhs, rhs in
                let l = lhs.followUpDate ?? Day(year: 9999, month: 12, day: 31)
                let r = rhs.followUpDate ?? Day(year: 9999, month: 12, day: 31)
                return (l, lhs.title) < (r, rhs.title)
            }
    }

    // MARK: - Projects

    /// An active project with no open action is stalled (P4).
    public static func isStalled(_ project: Project, in s: VaultSnapshot, today: Day) -> Bool {
        guard project.status == .active else { return false }
        return !visibleActions(s, today: today).contains { $0.project == project.id }
    }

    public static func stalledProjects(_ s: VaultSnapshot, today: Day) -> [Project] {
        s.projects.filter { isStalled($0, in: s, today: today) }
    }

    /// One row of the projects list (E4).
    public struct ProjectRow: Sendable, Equatable {
        public var project: Project
        public var activeActions: [Action]
        public var remainingSteps: Int
        public var isStalled: Bool

        public init(project: Project, activeActions: [Action], remainingSteps: Int, isStalled: Bool) {
            self.project = project
            self.activeActions = activeActions
            self.remainingSteps = remainingSteps
            self.isStalled = isStalled
        }
    }

    public static func projectRows(_ s: VaultSnapshot, today: Day) -> [ProjectRow] {
        let visible = visibleActions(s, today: today)
        return s.projects.map { project in
            ProjectRow(
                project: project,
                activeActions: visible
                    .filter { $0.project == project.id && $0.status.countsTowardCap }
                    .sorted { sortKey($0) < sortKey($1) },
                remainingSteps: project.openSteps.count,
                isStalled: isStalled(project, in: s, today: today))
        }
    }

    /// A2 — an action with two or more checkboxes is probably a project.
    public static func suggestsProject(_ action: Action) -> Bool { action.checkboxes.count >= 2 }

    // MARK: - Sidebar

    /// Live counts for the Mac sidebar (E3).
    public struct SidebarCounts: Sendable, Equatable {
        public var inbox: Int
        public var next: Int
        public var backlog: Int
        public var waiting: Int
        public var maybe: Int
        public var projects: Int
        public var deferred: Int

        public init(inbox: Int, next: Int, backlog: Int, waiting: Int, maybe: Int, projects: Int, deferred: Int) {
            self.inbox = inbox
            self.next = next
            self.backlog = backlog
            self.waiting = waiting
            self.maybe = maybe
            self.projects = projects
            self.deferred = deferred
        }
    }

    public static func sidebarCounts(_ s: VaultSnapshot, today: Day) -> SidebarCounts {
        let visible = visibleActions(s, today: today)
        return SidebarCounts(
            inbox: inboxQueue(s).count,
            next: visible.count { $0.status.countsTowardCap },
            backlog: visible.count { $0.status == .backlog },
            waiting: visible.count { $0.status == .waiting },
            maybe: visible.count { $0.status == .maybe },
            projects: s.projects.count { $0.status == .active },
            deferred: deferredList(s, today: today).count)
    }

    // MARK: - Signals (STYLEGUIDE §2.2)

    /// Every signal that applies to an action, highest step first. Max two are rendered (§3.2).
    public static func signals(
        for action: Action,
        today: Day,
        policy: StalenessPolicy = .default
    ) -> [Signal] {
        var out: [Signal] = []

        if let due = action.due {
            let delta = due.days(since: today)
            if delta < 0 {
                out.append(Signal(kind: .overdue(days: -delta), step: .overdue))
            } else if delta == 0 {
                out.append(Signal(kind: .dueToday, step: .attention))
            } else if delta <= policy.dueSoonDays {
                out.append(Signal(kind: .dueSoon(due), step: .aging))
            }
        }

        if action.status == .waiting, let followUp = action.followUpDate {
            let delta = followUp.days(since: today)
            if delta <= 0 {
                out.append(Signal(kind: .chase(days: -delta), step: .attention))
            } else if delta <= policy.followUpSoonDays {
                out.append(Signal(kind: .followUpSoon(followUp), step: .aging))
            }
        }

        if let deferDate = action.deferDate,
           deferDate <= today, today.days(since: deferDate) <= policy.returnedFromDeferDays {
            out.append(Signal(kind: .returnedFromDefer, step: .neutral))
        }

        // "Untouched" = file modification date (ARCHITECTURE §5); a status change rewrites the file.
        if let modified = action.modified {
            let days = today.days(since: Day(modified))
            if days > policy.actionAttentionDays {
                out.append(Signal(kind: .untouched(days: days), step: .attention))
            } else if days > policy.actionAgingDays {
                out.append(Signal(kind: .untouched(days: days), step: .aging))
            }
        }

        return out.sorted { $0.step > $1.step }
    }

    /// The `due` signal alone, for rows that show nothing else (STYLEGUIDE §2.2).
    public static func dueBadge(for action: Action, today: Day, policy: StalenessPolicy = .default) -> Signal? {
        signals(for: action, today: today, policy: policy).first {
            if case .overdue = $0.kind { return true }
            if case .dueToday = $0.kind { return true }
            if case .dueSoon = $0.kind { return true }
            return false
        }
    }

    /// The `back` badge for an item whose defer date just arrived (D1).
    public static func returnedFromDeferBadge(for action: Action, today: Day, policy: StalenessPolicy = .default) -> Signal? {
        signals(for: action, today: today, policy: policy).first {
            if case .returnedFromDefer = $0.kind { return true }
            return false
        }
    }

    public static func signals(for item: InboxItem, today: Day, policy: StalenessPolicy = .default) -> [Signal] {
        let days = today.days(since: Day(item.created))
        guard days > policy.inboxAgingDays else { return [] }
        return [Signal(kind: .inboxAge(days: days), step: .aging)]
    }

    public static func signals(for project: Project, in s: VaultSnapshot, today: Day) -> [Signal] {
        isStalled(project, in: s, today: today) ? [Signal(kind: .stalled, step: .attention)] : []
    }

    /// Sidebar / Next-view cap signal: `15/15` at the cap, overdue styling above it (§2.2).
    public static func capSignal(_ s: VaultSnapshot) -> Signal? {
        let count = countsTowardCap(s)
        let cap = s.config.nextCap
        if count > cap { return Signal(kind: .cap(count: count, cap: cap), step: .overdue) }
        if count == cap { return Signal(kind: .cap(count: count, cap: cap), step: .attention) }
        return nil
    }

    // MARK: - Archive and timeline

    /// Done or trashed actions whose `completedDate` is older than the archive threshold (A5).
    public static func archiveCandidates(
        _ s: VaultSnapshot,
        today: Day,
        policy: StalenessPolicy = .default
    ) -> [Action] {
        s.actions.filter { action in
            guard action.status.isClosed, let completed = action.completedDate else { return false }
            return today.days(since: Day(completed)) > policy.archiveAfterDays
        }
    }

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
        return out.sorted { ($0.day, $0.title) < ($1.day, $1.title) }
    }

    // MARK: - Helpers

    /// Stable ordering for lists that have no explicit order: oldest first, then title.
    // T11: the product order for Next is still open (due date? age? project?). Age + title for now.
    static func sortKey(_ action: Action) -> (Date, String) {
        (action.created ?? .distantPast, action.title)
    }
}
