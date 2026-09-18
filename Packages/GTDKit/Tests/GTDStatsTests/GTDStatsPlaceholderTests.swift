import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDStats

/// Placeholder so the target builds and `swift test` has something to run.
/// **T14 replaces this with the real suite.**
struct GTDStatsPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func isoWeekHelpers() {
        let week = ISOWeek(containing: Fixtures.today)
        #expect(week == ISOWeek(year: 2026, week: 38))
        #expect(week.monday == Day(year: 2026, month: 9, day: 14))
        #expect(week.days.count == 7)
        #expect(week.previous == ISOWeek(year: 2026, week: 37))
    }
}
