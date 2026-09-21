import Testing
import Foundation
import GTDModel
@testable import GTDStats

/// `WeeklyStats.compute` over small, hand-built snapshots — deterministic ages via an injected
/// `Calendar` with a fixed time zone, per the brief (never `.current`).
struct WeeklyStatsTests {

    /// UTC so `Date` → `Day` never depends on the machine running the tests.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    static func action(
        _ title: String,
        status: ActionStatus = .next,
        created: Date? = nil,
        modified: Date? = nil,
        completedDate: Date? = nil,
        followUpDate: Day? = nil,
        deferDate: Day? = nil
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"), title: title, status: status,
            deferDate: deferDate, waitingFor: status == .waiting ? "Someone" : nil,
            followUpDate: status == .waiting ? followUpDate : nil,
            created: created, completedDate: completedDate, modified: modified)
    }

    static func project(_ title: String, status: ProjectStatus = .active) -> Project {
        Project(id: NoteID(path: "Projects/\(title)/\(title).md"), title: title, status: status)
    }

    // MARK: Empty data

    @Test func emptySnapshotIsAllZeroes() {
        let week = ISOWeek(year: 2026, week: 38)
        let stats = WeeklyStats.compute(snapshot: .empty, week: week, calendar: Self.calendar)
        #expect(stats.year == 2026)
        #expect(stats.week == 38)
        #expect(stats.captured == 0)
        #expect(stats.processed == 0)
        #expect(stats.doneThisWeek == 0)
        #expect(stats.medianNextAgeDays == 0)
        #expect(stats.oldestNext.isEmpty)
        #expect(stats.untouchedOver30Days == 0)
        #expect(stats.waitingByAgeDays.isEmpty)
        #expect(stats.stalledProjects == 0)
    }

    // MARK: Captured vs. processed

    @Test func capturedCountsRemainingInboxAndFiledActionsForTheWeek() {
        // Week of 2026-09-14 (Mon) … 2026-09-20 (Sun).
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        // Still queued, captured this week.
        snapshot.inbox = [
            InboxItem(id: NoteID(path: "Inbox/a.md"), text: "a", created: Self.date(2026, 9, 15)),
        ]
        // Filed this week (its `created` survived from the inbox capture) — counts as both
        // captured and processed.
        snapshot.actions = [
            Self.action("Filed this week", created: Self.date(2026, 9, 16)),
            // Captured a different week — must not be counted at all.
            Self.action("Filed last week", created: Self.date(2026, 9, 7)),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.captured == 2)   // 1 inbox item + 1 action
        #expect(stats.processed == 1)  // the action alone
    }

    @Test func doneThisWeekUsesCompletedDate() {
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            Self.action("Done in week", status: .done, completedDate: Self.date(2026, 9, 17)),
            Self.action("Done earlier", status: .done, completedDate: Self.date(2026, 9, 1)),
            Self.action("Not done", status: .next),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.doneThisWeek == 1)
    }

    // MARK: Next age distribution

    @Test func medianAndOldestNextIgnoreActionsWithNoCreatedDate() {
        // Review day = 2026-09-20 (the week's Sunday).
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            Self.action("10 days old", created: Self.date(2026, 9, 10)),   // age 10
            Self.action("4 days old", created: Self.date(2026, 9, 16)),    // age 4
            Self.action("20 days old", created: Self.date(2026, 8, 31)),   // age 20
            Self.action("No created date"),                                 // excluded
            Self.action("Someday, not Next", status: .someday, created: Self.date(2026, 9, 1)),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.medianNextAgeDays == 10)   // median of [4, 10, 20]
        #expect(stats.oldestNext.map { $0.title } == ["20 days old", "10 days old", "4 days old"])
    }

    @Test func medianAveragesTheTwoMiddleAgesOnAnEvenCount() {
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        // Ages relative to 2026-09-20: 1, 3, 5, 9.
        snapshot.actions = [
            Self.action("a", created: Self.date(2026, 9, 19)),
            Self.action("b", created: Self.date(2026, 9, 17)),
            Self.action("c", created: Self.date(2026, 9, 15)),
            Self.action("d", created: Self.date(2026, 9, 11)),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.medianNextAgeDays == 4)   // (3 + 5) / 2
    }

    @Test func inProgressCountsTowardNextAgeLikeCap() {
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [Self.action("Working on it", status: .inProgress, created: Self.date(2026, 9, 10))]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.medianNextAgeDays == 10)
    }

    @Test func deferredNextItemsAreExcludedLikeEverywhereElse() {
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            Self.action("Hidden by defer", created: Self.date(2026, 9, 1),
                        deferDate: Day(year: 2026, month: 12, day: 1)),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.oldestNext.isEmpty)
    }

    // MARK: Untouched > 30 days

    @Test func untouchedOver30DaysUsesModifiedNotCreated() {
        let week = ISOWeek(year: 2026, week: 38)   // review day 2026-09-20
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            // Untouched for 31 days (> 30) — counts.
            Self.action("Stale", created: Self.date(2026, 1, 1), modified: Self.date(2026, 8, 20)),
            // Untouched for exactly 30 days — does not count (threshold is "> 30").
            Self.action("Borderline", modified: Self.date(2026, 8, 21)),
            // Recently touched — does not count even though old.
            Self.action("Recently touched", created: Self.date(2026, 1, 1), modified: Self.date(2026, 9, 19)),
            // Closed actions are never stale.
            Self.action("Done", status: .done, modified: Self.date(2026, 1, 1)),
            // No modified date at all — excluded, not assumed stale.
            Self.action("Never touched"),
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.untouchedOver30Days == 1)
    }

    // MARK: Waiting by age

    @Test func waitingByAgeUsesModifiedFallingBackToCreated() {
        let week = ISOWeek(year: 2026, week: 38)   // review day 2026-09-20
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            Self.action("Has modified", status: .waiting, created: Self.date(2026, 1, 1),
                        modified: Self.date(2026, 9, 10)),   // age 10
            Self.action("No modified", status: .waiting, created: Self.date(2026, 9, 15)),   // age 5
        ]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.waitingByAgeDays == [5, 10])
    }

    // MARK: Stalled projects

    @Test func stalledProjectsMatchesRules() {
        let week = ISOWeek(year: 2026, week: 38)
        var snapshot = VaultSnapshot.empty
        let stalled = Self.project("No open actions")
        let healthy = Self.project("Has an action")
        snapshot.projects = [stalled, healthy]
        snapshot.actions = [
            Self.action("Open", status: .next, created: Self.date(2026, 9, 1)),
        ]
        snapshot.actions[0].project = healthy.id
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.stalledProjects == 1)
    }

    // MARK: Year-boundary week

    @Test func computesForAYearBoundaryWeekWithoutCrashing() {
        // KW 53 2020: 2020-12-28 … 2021-01-03.
        let week = ISOWeek(year: 2020, week: 53)
        var snapshot = VaultSnapshot.empty
        snapshot.inbox = [InboxItem(id: NoteID(path: "Inbox/x.md"), text: "x", created: Self.date(2021, 1, 1))]
        snapshot.actions = [Self.action("Spans the boundary", created: Self.date(2020, 12, 30))]
        let stats = WeeklyStats.compute(snapshot: snapshot, week: week, calendar: Self.calendar)
        #expect(stats.year == 2020)
        #expect(stats.week == 53)
        #expect(stats.captured == 2)
        #expect(stats.processed == 1)
    }
}
