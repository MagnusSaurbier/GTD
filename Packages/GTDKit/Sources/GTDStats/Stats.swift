import Foundation
import GTDModel

/// Live numbers for the weekly review's systems check (§10.3).
/// Pure: everything is computed from the snapshot, nothing is persisted (ARCHITECTURE §6).
public struct WeeklyStats: Sendable, Equatable {
    public var year: Int
    public var week: Int
    public var captured: Int
    public var processed: Int
    public var doneThisWeek: Int
    /// Age in days of the Next items: median and the three oldest.
    public var medianNextAgeDays: Int
    public var oldestNext: [NoteID]
    public var untouchedOver30Days: Int
    public var waitingByAgeDays: [Int]
    public var stalledProjects: Int

    public init(
        year: Int,
        week: Int,
        captured: Int = 0,
        processed: Int = 0,
        doneThisWeek: Int = 0,
        medianNextAgeDays: Int = 0,
        oldestNext: [NoteID] = [],
        untouchedOver30Days: Int = 0,
        waitingByAgeDays: [Int] = [],
        stalledProjects: Int = 0
    ) {
        self.year = year
        self.week = week
        self.captured = captured
        self.processed = processed
        self.doneThisWeek = doneThisWeek
        self.medianNextAgeDays = medianNextAgeDays
        self.oldestNext = oldestNext
        self.untouchedOver30Days = untouchedOver30Days
        self.waitingByAgeDays = waitingByAgeDays
        self.stalledProjects = stalledProjects
    }

    /// Computes the systems-check numbers for `week` (§10.3) from `snapshot` alone — nothing is
    /// persisted (ARCHITECTURE §6), so every figure is derived from fields the snapshot already
    /// carries: `InboxItem.created`, `Action.created`/`.modified`/`.completedDate`, and
    /// `Rules.visibleActions` / `Rules.stalledProjects`.
    ///
    /// All "today"-relative numbers (ages, staleness, stalled projects) are anchored on the
    /// **last day of `week`** (its Sunday) rather than the real current day, so a review done a
    /// few days after the week closes still sees the week's own numbers, and the function stays
    /// pure in its parameters.
    ///
    /// ### The captured/processed approximation
    /// The vault has no persisted history of *when* an inbox item was filed — only `created`
    /// (preserved from the inbox capture onto the resulting `Action`) and whether the item is
    /// still an `InboxItem` right now. So both numbers are derived from the same signal —
    /// whether something with a `created` date in `week` is still sitting in the inbox, or has
    /// already become an `Action`:
    /// - **captured** = inbox items still queued with `created` in `week`, plus actions with
    ///   `created` in `week` (their capture timestamp survived filing).
    /// - **processed** = the subset of `captured` that already left the inbox, i.e. the actions
    ///   half of that count.
    ///
    /// This undercounts two cases that have no `created` marker in the snapshot at all:
    /// an item captured and then trashed or filed as a `Knowledge` note (its file is gone from
    /// both `inbox` and `actions`), and a new project with no initial actions (`Project` has no
    /// `created` field — ARCHITECTURE §4). It also cannot tell "captured earlier, processed this
    /// week" from "captured this week, still queued": both are real GTD events the wizard cares
    /// about, but only the second is visible without a filed-at log. Good enough for a "does the
    /// inbox move" gut check; not an audit trail.
    public static func compute(
        snapshot: VaultSnapshot,
        week: ISOWeek,
        calendar: Calendar = .current
    ) -> WeeklyStats {
        let weekDays = Set(week.days)
        // The review naturally lands on or after the week it covers; anchoring "today" on the
        // week's last day keeps every figure below a pure function of `week` alone.
        let reviewDay = week.days.last ?? week.monday

        func fallsInWeek(_ date: Date) -> Bool { weekDays.contains(Day(date, calendar: calendar)) }
        func age(since date: Date) -> Int { reviewDay.days(since: Day(date, calendar: calendar)) }

        let inboxCapturedThisWeek = snapshot.inbox.filter { fallsInWeek($0.created) }.count
        let actionsCapturedThisWeek = snapshot.actions.filter { $0.created.map(fallsInWeek) ?? false }

        let doneThisWeek = snapshot.actions.count {
            $0.status == .done && ($0.completedDate.map(fallsInWeek) ?? false)
        }

        // "Next" occupancy matches `Rules`/`ActionStatus.countsTowardCap` everywhere else in the
        // app (`in-progress` counts too); hidden (deferred) items are excluded, as in every list.
        let nextItems = Rules.visibleActions(snapshot, today: reviewDay)
            .filter { $0.status.countsTowardCap }
        // Age = time since capture (`created`); items with no `created` (hand-edited notes) are
        // left out of the distribution rather than faked to age 0 (§1 "no lying defaults").
        let nextAges: [(id: NoteID, days: Int)] = nextItems.compactMap { action in
            guard let created = action.created else { return nil }
            return (action.id, age(since: created))
        }
        let oldestNext = nextAges
            .sorted { $0.days != $1.days ? $0.days > $1.days : $0.id.path < $1.id.path }
            .prefix(3)
            .map(\.id)

        // "Untouched" = file modification date, same definition as the `untouched` signal
        // (STYLEGUIDE §2.2, `Rules.signals`); reuse its threshold so the two numbers agree.
        let untouchedThreshold = StalenessPolicy.default.actionAttentionDays
        let untouchedOver30Days = snapshot.actions.count { action in
            guard !action.status.isClosed, let modified = action.modified else { return false }
            return age(since: modified) > untouchedThreshold
        }

        // A status change rewrites the file, so `modified` also approximates "waiting since".
        let waitingByAgeDays = snapshot.actions
            .filter { $0.status == .waiting }
            .compactMap { action in (action.modified ?? action.created).map(age(since:)) }
            .sorted()

        return WeeklyStats(
            year: week.year,
            week: week.week,
            captured: inboxCapturedThisWeek + actionsCapturedThisWeek.count,
            processed: actionsCapturedThisWeek.count,
            doneThisWeek: doneThisWeek,
            medianNextAgeDays: median(nextAges.map(\.days)),
            oldestNext: Array(oldestNext),
            untouchedOver30Days: untouchedOver30Days,
            waitingByAgeDays: waitingByAgeDays,
            stalledProjects: Rules.stalledProjects(snapshot, today: reviewDay).count)
    }

    /// Rounds to the nearest day; averages the two middle ages on an even count.
    private static func median(_ ages: [Int]) -> Int {
        guard !ages.isEmpty else { return 0 }
        let sorted = ages.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Int((Double(sorted[mid - 1] + sorted[mid]) / 2).rounded())
        }
        return sorted[mid]
    }
}

/// An ISO week (`KW`), Monday-based.
public struct ISOWeek: Sendable, Equatable, Hashable {
    public var year: Int
    public var week: Int

    public init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    public init(containing day: Day) {
        let iso = day.isoWeek
        self.init(year: iso.year, week: iso.week)
    }

    /// Monday of this week. Derived purely from `Day` arithmetic.
    public var monday: Day {
        let jan4 = Day(year: year, month: 1, day: 4)   // always in ISO week 1
        return jan4.startOfISOWeek.adding(days: (week - 1) * 7)
    }

    public var days: [Day] { (0..<7).map { monday.adding(days: $0) } }

    public var previous: ISOWeek { ISOWeek(containing: monday.adding(days: -7)) }
}

/// Per-step 7-day heatmap for one routine (§10.3).
public struct RoutineAudit: Sendable, Equatable {
    public struct Cell: Sendable, Equatable {
        public var day: Day
        public var result: RoutineStepResult?   // nil = not logged
        public init(day: Day, result: RoutineStepResult?) {
            self.day = day
            self.result = result
        }
    }

    public struct Row: Sendable, Equatable {
        public var stepID: String
        public var title: String
        public var cells: [Cell]
        /// 0…100.
        public var completionPercent: Int
        public init(stepID: String, title: String, cells: [Cell], completionPercent: Int) {
            self.stepID = stepID
            self.title = title
            self.cells = cells
            self.completionPercent = completionPercent
        }
    }

    public var routine: NoteID
    public var title: String
    public var rows: [Row]
    public var completionPercent: Int
    /// Percentage points versus the previous seven days.
    public var trend: Int

    public init(routine: NoteID, title: String, rows: [Row], completionPercent: Int, trend: Int) {
        self.routine = routine
        self.title = title
        self.rows = rows
        self.completionPercent = completionPercent
        self.trend = trend
    }

    /// One 7-day heatmap per routine, the 7 days ending on and including `endingOn` (§10.3).
    ///
    /// Rows follow the routine's **current** template step list: a step the template dropped
    /// gets no row (its old log entries are simply never looked up), and a step the template
    /// just gained shows "not logged" for every day before it existed — both fall out of
    /// building rows from `routine.steps` rather than from whatever step ids happen to appear
    /// in `log`, no special-casing needed.
    ///
    /// `log` is the snapshot's already-merged-across-devices 14-day tail (`VaultSnapshot
    /// .routineLog`, ARCHITECTURE §4); if more than one device logged the same routine/step/day,
    /// the entry with the latest `at` wins (multi-device merge, N3).
    public static func compute(
        routines: [Routine],
        log: [RoutineLogEntry],
        endingOn day: Day
    ) -> [RoutineAudit] {
        let currentDays = last7Days(endingOn: day)
        let previousDays = last7Days(endingOn: day.adding(days: -7))
        return routines.map { routine in
            let merged = mergedResults(routineTitle: routine.title, log: log)
            let currentRows = rows(for: routine, merged: merged, days: currentDays)
            let currentPercent = percentage(rows: currentRows)
            let previousPercent = percentage(steps: routine.steps, merged: merged, days: previousDays)
            return RoutineAudit(
                routine: routine.id,
                title: routine.title,
                rows: currentRows,
                completionPercent: currentPercent,
                trend: currentPercent - previousPercent)
        }
    }

    // MARK: - Private helpers

    private struct CellKey: Hashable { var day: Day; var step: String }

    private static func last7Days(endingOn day: Day) -> [Day] {
        (0..<7).map { day.adding(days: $0 - 6) }
    }

    /// Log entries for this routine, one result per (day, step) — latest `at` wins when several
    /// devices logged the same cell.
    private static func mergedResults(
        routineTitle: String, log: [RoutineLogEntry]
    ) -> [CellKey: RoutineStepResult] {
        var latest: [CellKey: RoutineLogEntry] = [:]
        for entry in log where entry.routine == routineTitle {
            let key = CellKey(day: entry.day, step: entry.step)
            if let existing = latest[key], existing.at >= entry.at { continue }
            latest[key] = entry
        }
        return latest.mapValues(\.result)
    }

    private static func rows(
        for routine: Routine, merged: [CellKey: RoutineStepResult], days: [Day]
    ) -> [RoutineAudit.Row] {
        routine.steps.map { step in
            let cells = days.map { RoutineAudit.Cell(day: $0, result: merged[CellKey(day: $0, step: step.id)]) }
            let done = cells.count { $0.result == .done }
            return RoutineAudit.Row(
                stepID: step.id, title: step.title, cells: cells,
                completionPercent: percentage(done, of: cells.count))
        }
    }

    private static func percentage(rows: [RoutineAudit.Row]) -> Int {
        let total = rows.count * 7
        let done = rows.reduce(0) { $0 + $1.cells.count { $0.result == .done } }
        return percentage(done, of: total)
    }

    /// Same aggregate as `percentage(rows:)`, without materialising rows — used for the
    /// previous-week comparison, which only needs the one number.
    private static func percentage(
        steps: [RoutineStep], merged: [CellKey: RoutineStepResult], days: [Day]
    ) -> Int {
        var done = 0
        for step in steps {
            for d in days where merged[CellKey(day: d, step: step.id)] == .done { done += 1 }
        }
        return percentage(done, of: steps.count * days.count)
    }

    private static func percentage(_ numerator: Int, of denominator: Int) -> Int {
        guard denominator > 0 else { return 0 }
        return Int((Double(numerator) / Double(denominator) * 100).rounded())
    }
}
