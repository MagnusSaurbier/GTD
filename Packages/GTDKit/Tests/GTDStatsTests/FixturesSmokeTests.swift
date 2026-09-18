import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDStats

/// Runs both `compute` functions over `GTDFixtures.sampleSnapshot` — the realistic data the
/// synthetic unit tests above don't exercise (multiple projects/areas, 10 days of real routine
/// log, mixed statuses). Not a source of truth for exact numbers, just "doesn't crash, looks sane".
struct FixturesSmokeTests {

    @Test func weeklyStatsOverTheFixtureVault() {
        let week = ISOWeek(containing: Fixtures.today)
        let stats = WeeklyStats.compute(
            snapshot: Fixtures.sampleSnapshot, week: week, calendar: Fixtures.calendar)
        #expect(stats.year == week.year)
        #expect(stats.week == week.week)
        #expect(stats.captured >= 0)
        #expect(stats.processed >= 0)
        #expect(stats.processed <= stats.captured)
        #expect(stats.stalledProjects >= 1)   // the fixture brief calls for a stalled project
        #expect(!stats.waitingByAgeDays.isEmpty)   // the fixture has an overdue waiting item
    }

    @Test func routineAuditOverTheFixtureVault() {
        let audits = RoutineAudit.compute(
            routines: Fixtures.sampleSnapshot.routines,
            log: Fixtures.sampleSnapshot.routineLog,
            endingOn: Fixtures.today)
        #expect(audits.count == Fixtures.sampleSnapshot.routines.count)
        for audit in audits {
            #expect(audit.rows.count == Fixtures.sampleSnapshot.routines.first { $0.id == audit.routine }?.steps.count)
            for row in audit.rows { #expect(row.cells.count == 7) }
            #expect((0...100).contains(audit.completionPercent))
        }
        // 10 days of logged fixture data ⇒ at least some cells should be logged, not all nil.
        #expect(audits.contains { $0.rows.contains { $0.cells.contains { $0.result != nil } } })
    }
}
