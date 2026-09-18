import Foundation
import GTDModel

/// Live numbers for the weekly review's systems check (§10.3). **Owned by T14.**
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

    /// **T14.** Returns zeroed stats for the requested week until then.
    public static func compute(
        snapshot: VaultSnapshot,
        week: ISOWeek,
        calendar: Calendar = .current
    ) -> WeeklyStats {
        WeeklyStats(year: week.year, week: week.week)
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

/// Per-step 7-day heatmap for one routine (§10.3). **Owned by T14.**
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

    /// **T14.** Returns an empty audit per routine until then.
    public static func compute(
        routines: [Routine],
        log: [RoutineLogEntry],
        endingOn day: Day
    ) -> [RoutineAudit] {
        routines.map {
            RoutineAudit(routine: $0.id, title: $0.title, rows: [], completionPercent: 0, trend: 0)
        }
    }
}
