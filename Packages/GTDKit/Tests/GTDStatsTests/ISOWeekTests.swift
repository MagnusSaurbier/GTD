import Testing
import Foundation
import GTDModel
@testable import GTDStats

/// ISO-8601 week maths, with the year-boundary cases (KW 52/53/1) the brief calls out.
/// All of it is `Day` integer arithmetic (no `Calendar`), so these are exact, not "close enough".
struct ISOWeekTests {

    // MARK: `Day.isoWeek` at year boundaries

    @Test func week1StartsOnTheMondayOnOrBeforeJan4() {
        // 2016-01-04 is a Monday → week 1 of 2016 starts exactly there.
        #expect(Day(year: 2016, month: 1, day: 4).isoWeek == (2016, 1))
    }

    @Test func lateDecemberCanBelongToNextYearsWeek1() {
        // 2024-12-30/31 are Mon/Tue; their ISO Thursday (2025-01-02) is in 2025, so both are
        // already week 1 of 2025, not week 53 of 2024.
        #expect(Day(year: 2024, month: 12, day: 30).isoWeek == (2025, 1))
        #expect(Day(year: 2024, month: 12, day: 31).isoWeek == (2025, 1))
        #expect(Day(year: 2025, month: 1, day: 1).isoWeek == (2025, 1))
    }

    @Test func earlyJanuaryCanBelongToThePreviousYearsWeek53() {
        // 2015 has 53 ISO weeks (2015-12-31 is a Thursday). 2016-01-01 (Friday) falls in the
        // same week, so it is still week 53 of 2015, not week 1 of 2016.
        #expect(Day(year: 2015, month: 12, day: 31).isoWeek == (2015, 53))
        #expect(Day(year: 2016, month: 1, day: 1).isoWeek == (2015, 53))
    }

    @Test func fourDayYearWithA53rdWeek() {
        // 2020-12-31 is a Thursday ⇒ 2020 has a week 53; 2021-01-01 (Friday) shares it.
        #expect(Day(year: 2020, month: 12, day: 31).isoWeek == (2020, 53))
        #expect(Day(year: 2021, month: 1, day: 1).isoWeek == (2020, 53))
        #expect(Day(year: 2021, month: 1, day: 4).isoWeek == (2021, 1))
    }

    // MARK: `ISOWeek` round-trips at the same boundaries

    @Test func isoWeekContainingRoundTripsAcrossYearBoundary() {
        for day in [Day(year: 2020, month: 12, day: 28), Day(year: 2021, month: 1, day: 3),
                    Day(year: 2024, month: 12, day: 30), Day(year: 2025, month: 1, day: 5)] {
            let week = ISOWeek(containing: day)
            #expect(week.days.contains(day))
        }
    }

    @Test func week53Of2020HasSevenDaysEndingBeforeWeek1Of2021() {
        let week53 = ISOWeek(year: 2020, week: 53)
        #expect(week53.monday == Day(year: 2020, month: 12, day: 28))
        #expect(week53.days.count == 7)
        #expect(week53.days.last == Day(year: 2021, month: 1, day: 3))
    }

    @Test func previousCrossesTheYearBoundaryBothWays() {
        #expect(ISOWeek(year: 2021, week: 1).previous == ISOWeek(year: 2020, week: 53))
        #expect(ISOWeek(year: 2020, week: 53).previous == ISOWeek(year: 2020, week: 52))
        #expect(ISOWeek(year: 2025, week: 1).previous == ISOWeek(year: 2024, week: 52))
    }

    @Test func mondayIsStableUnderContainingAnyWeekday() {
        let week = ISOWeek(year: 2026, week: 38)
        for offset in 0..<7 {
            #expect(ISOWeek(containing: week.monday.adding(days: offset)) == week)
        }
    }
}
