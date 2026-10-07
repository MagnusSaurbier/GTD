import Foundation

/// Pure derived queries over a `VaultSnapshot` — the read half of the GTD semantics.
/// Views and backends never re-implement these.
///
/// Every query is **total and deterministic**: each sort uses a total order (a unique `NoteID`
/// is always the last tiebreaker), so the same snapshot always produces the same list.
///
/// Conversions from `Date` to `Day` take a `calendar` parameter that defaults to `.current`;
/// the reducer passes `env.calendar` so its results never depend on the machine's time zone.
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

    /// A5/D1 — open actions are listed, except a deferred Someday item before its date: it is
    /// hidden from every list until then and comes back to Someday (#86). Every other deferral
    /// is a who-less waiting item, listed in Waiting (`DeferIsWaiting.swift`).
    public static func isVisible(_ action: Action, today: Day) -> Bool {
        guard !action.status.isClosed else { return false }        // A5
        if let deferDate = action.deferDate, deferDate > today { return false }
        return true
    }

    /// Everything a list may show today: open actions not hidden by a defer date (A5, D1).
    public static func visibleActions(_ s: VaultSnapshot, today: Day) -> [Action] {
        s.actions.filter { isVisible($0, today: today) }
    }

    // MARK: - Next and the cap

    /// How many actions occupy a Next slot **today** (A3; ARCHITECTURE §6: `in-progress`
    /// counts too).
    ///
    /// R-2/#86: a deferred item is a who-less waiting item and holds no slot while it waits;
    /// on its follow-up date it is back in Next and counts again — possibly pushing Next over
    /// the cap, which is shown (`16/15`) and never repaired automatically. `checkCap` only
    /// blocks commands that make the number worse.
    public static func countsTowardCap(_ s: VaultSnapshot, today: Day) -> Int {
        s.actions.count { occupiesNext($0, today: today) }
    }

    /// The action is in Next today: `next`/`in-progress`, or a deferral that is back (#86).
    static func occupiesNext(_ action: Action, today: Day) -> Bool {
        guard isVisible(action, today: today) else { return false }
        return action.status.countsTowardCap || isBackInNext(action, today: today)
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
            .filter { occupiesNext($0, today: today) }
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

    // MARK: - In progress board (#87)

    /// One column of the In progress board: the visible actions in `status` (one of
    /// `ActionStatus.boardStatuses`), filtered by context (E1: at least one of the chosen ones)
    /// and by project (`nil` = every project, and actions without one). Hidden (deferred)
    /// actions stay hidden, as in every list (D1). Ordered like Next: nearest `due`, then the
    /// oldest capture, then the path — total, so the board never reshuffles.
    public static func boardColumn(
        _ s: VaultSnapshot,
        status: ActionStatus,
        contexts: [String] = [],
        project: NoteID? = nil,
        today: Day
    ) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.status == status }
            .filter { matches($0, contexts: contexts) }
            .filter { project == nil || $0.project == project }
            .sorted(by: nextIsOrdered)
    }

    /// The projects the board's project filter offers: every project that one of the board's
    /// visible actions names, by title then path. A dangling link (#53) is offered too — under
    /// its file name — so such a card can still be filtered to.
    public static func boardProjects(_ s: VaultSnapshot, today: Day) -> [NoteID] {
        let ids = Set(visibleActions(s, today: today)
            .filter { $0.status.isOnBoard }
            .compactMap(\.project))
        func title(_ id: NoteID) -> String { s.project(id)?.title ?? id.title }
        return ids.sorted { (title($0), $0.path) < (title($1), $1.path) }
    }

    // MARK: - Waiting

    /// Waiting items whose follow-up date has arrived — shown above Next as "chase" (W2).
    /// Only items with a who: a who-less one is back in Next itself (#86).
    public static func chaseItems(_ s: VaultSnapshot, today: Day) -> [Action] {
        waitingList(s, today: today).filter { action in
            guard let followUp = action.followUpDate else { return false }
            return followUp <= today
        }
    }

    /// The waiting view (W2), sorted by staleness: the longest-overdue follow-up first,
    /// then the oldest capture. Deferred items are in it too — a deferral is a who-less waiting
    /// item — until their follow-up date puts them back in Next (#86).
    public static func waitingList(_ s: VaultSnapshot, today: Day) -> [Action] {
        visibleActions(s, today: today)
            .filter { $0.status == .waiting && !isBackInNext($0, today: today) }
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
    /// stalled list. A waiting item does (deferred ones included, #86): the project is moving,
    /// it just waits.
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
    /// `openActions` apply: `someday` is not a commitment.
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

    /// Rows for the projects list (E4).
    ///
    /// **Area-less projects come first** — the `Projects/no_area/` ones and any legacy project
    /// still sitting directly under `Projects/` (R-6, P1). They are listed *without* a section
    /// header, exactly as ungrouped actions are (ARCHITECTURE §6): STYLEGUIDE forbids inventing a
    /// "No area" heading for something the user has simply not decided yet.
    /// Within that split: active projects first, then on-hold, someday, done; then title, then
    /// path, so the order is total.
    public static func projectRows(_ s: VaultSnapshot, today: Day) -> [ProjectRow] {
        let byProject = visibleActionsByProject(s, today: today)
        return s.projects
            .map { project in
                let visible = byProject[project.id] ?? []
                return ProjectRow(
                    project: project,
                    activeActions: visible
                        .filter { occupiesNext($0, today: today) }
                        .sorted(by: nextIsOrdered),
                    remainingSteps: project.openSteps.count,
                    isStalled: isStalled(project, visible: visible))
            }
            .sorted { lhs, rhs in
                let leftHasArea = lhs.project.area != nil
                let rightHasArea = rhs.project.area != nil
                if leftHasArea != rightHasArea { return !leftHasArea }
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

    // MARK: - Lists (§5a)

    /// Every list, alphabetically (case-insensitively, then by name so the order is total).
    /// Includes the empty ones — a list exists because its folder does (L2).
    public static func lists(_ s: VaultSnapshot) -> [GTDList] {
        s.lists.sorted { lhs, rhs in
            let l = lhs.name.lowercased()
            let r = rhs.name.lowercased()
            if l != r { return l < r }
            return lhs.name < rhs.name
        }
    }

    /// One row of the Lists home / the Mac sidebar section (L2, L5).
    public struct ListRow: Sendable, Equatable {
        public var list: GTDList
        /// Items still to read / watch / buy.
        public var openCount: Int
        /// Items in `Lists/<name>/Done/` (L3).
        public var finishedCount: Int

        public init(list: GTDList, openCount: Int, finishedCount: Int) {
            self.list = list
            self.openCount = openCount
            self.finishedCount = finishedCount
        }
    }

    /// The lists with their counts, in `lists(_:)` order (L2).
    public static func listRows(_ s: VaultSnapshot) -> [ListRow] {
        var open: [String: Int] = [:]
        var finished: [String: Int] = [:]
        for item in s.listItems {
            if item.isFinished { finished[item.list, default: 0] += 1 }
            else { open[item.list, default: 0] += 1 }
        }
        return lists(s).map {
            ListRow(
                list: $0,
                openCount: open[$0.name] ?? 0,
                finishedCount: finished[$0.name] ?? 0)
        }
    }

    /// The items of one list (L1). `finished: false` is the list itself, `true` its `Done/` log
    /// (L3). Newest capture first, then by path — a list item has no staleness, so age is not a
    /// signal, only an order.
    public static func listItems(
        _ s: VaultSnapshot, in list: String, finished: Bool = false
    ) -> [ListItem] {
        s.listItems
            .filter { GTDList.sameName($0.list, list) && $0.isFinished == finished }
            .sorted { lhs, rhs in
                let l = lhs.created ?? .distantPast
                let r = rhs.created ?? .distantPast
                if l != r { return l > r }
                return lhs.id.path < rhs.id.path
            }
    }

    /// Open items across all lists — the single Mac sidebar row's count and the iPhone tab's
    /// badge (E3, L5). Finished items are a log, not a to-do.
    public static func openListItemCount(_ s: VaultSnapshot) -> Int {
        s.listItems.count { !$0.isFinished }
    }

    /// I4b/R-5 — the lists the inbox navbar offers, in the user's order.
    ///
    /// `GTDConfig.favouriteLists` is `nil` until the user has chosen: the default is then the
    /// **first four lists alphabetically**, derived here and never written to the vault. A stored
    /// choice that names a list which no longer exists is skipped rather than shown as a ghost.
    public static func favouriteLists(_ s: VaultSnapshot) -> [GTDList] {
        let all = lists(s)
        guard let chosen = s.config.favouriteLists else { return Array(all.prefix(4)) }
        return chosen.compactMap { name in all.first { GTDList.sameName($0.name, name) } }
    }

    // MARK: - Sidebar

    /// Live counts for the Mac sidebar (E3). Every count matches the list the row opens: a
    /// deferral counts under `waiting` until it is back, then under `next` (#86).
    public struct SidebarCounts: Sendable, Equatable {
        public var inbox: Int
        public var next: Int
        public var someday: Int
        public var waiting: Int
        /// Open items across every list — one sidebar row for all lists (E3, §5a).
        public var lists: Int
        public var projects: Int
        /// #87 — every card on the In progress board (in progress + agent + review).
        public var inProgress: Int

        public init(
            inbox: Int,
            next: Int,
            someday: Int,
            waiting: Int,
            lists: Int,
            projects: Int,
            inProgress: Int = 0
        ) {
            self.inbox = inbox
            self.next = next
            self.someday = someday
            self.waiting = waiting
            self.lists = lists
            self.projects = projects
            self.inProgress = inProgress
        }
    }

    /// E3 — the sidebar's live counts.
    public static func sidebarCounts(_ s: VaultSnapshot, today: Day) -> SidebarCounts {
        let visible = visibleActions(s, today: today)
        return SidebarCounts(
            inbox: inboxQueue(s).count,
            next: visible.count { occupiesNext($0, today: today) },
            someday: visible.count { $0.status == .someday },
            waiting: visible.count { $0.status == .waiting && !isBackInNext($0, today: today) },
            lists: openListItemCount(s),
            projects: s.projects.count { $0.status == .active },
            inProgress: visible.count { $0.status.isOnBoard })
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

        // waiting: follow-up soon / passed ⇒ chase (W2). A who-less one is a deferral: on its
        // date it is back in Next with the `back` badge instead (D1, #86; the badge lives for
        // `returnedFromDeferDays` days).
        if action.status == .waiting, let followUp = action.followUpDate {
            let delta = followUp.days(since: today)
            if action.isWhoLessWaiting, delta <= 0 {
                if -delta < policy.returnedFromDeferDays {
                    out.append(Signal(kind: .returnedFromDefer, step: .neutral))
                }
            } else if delta <= 0 {
                out.append(Signal(kind: .chase(days: -delta), step: .attention))
            } else if delta <= policy.followUpSoonDays {
                out.append(Signal(kind: .followUpSoon(followUp), step: .aging))
            }
        }

        // D1/#86 — a deferred Someday item came back to Someday today.
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

    /// The `back` badge for a deferral whose follow-up date has just arrived (D1, #86).
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

    /// A deferral to Next is a who-less follow-up (#86); `deferred` marks the day a deferred
    /// Someday item comes back.
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

    /// Defer, due and follow-up dates of all open actions in `from...to` (D3; a deferral to
    /// Next shows as its follow-up date, a deferred Someday item as its defer date, #86).
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
        case .updateConfig, .logRoutineStep, .setRoutineTime, .saveWeeklyReview, .archiveCompleted,
             .setFavouriteLists, .pruneFavouriteLists, .setListIcon:
            false
        // `createList` only creates a folder, and undoing it would mean removing a directory —
        // the hard delete this app never does (ARCHITECTURE §6). Nothing is lost by leaving an
        // empty folder, so it is not offered as an undo at all.
        case .createList:
            false
        case .renameInboxItem, .editInboxBody, .fileInbox, .deferInboxToReview, .createAction, .updateAction,
             .setStatus, .trashAction, .complete, .toggleCheckbox, .convertActionToProject,
             .createArea, .createProject, .updateProject, .promoteStep, .linkStep,
             .renameList, .removeList, .addListItem, .updateListItem, .completeListItem,
             .trashListItem, .promoteListItem, .moveActionToList:
            true
        }
    }
}
