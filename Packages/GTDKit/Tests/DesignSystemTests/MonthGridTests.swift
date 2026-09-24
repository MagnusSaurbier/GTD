import Testing
import GTDModel
@testable import DesignSystem

/// The calendar arithmetic behind `DayPicker` (the app's own date grid, which replaced the stock
/// graphical `DatePicker` whose clicks never reached the chip's binding on macOS).
struct MonthGridTests {

    @Test func theGridIsSixFullWeeksStartingOnMonday() {
        let grid = MonthGrid(year: 2026, month: 9)
        #expect(grid.weeks.count == 6)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        #expect(grid.weeks.allSatisfy { $0.first?.isoWeekday == 1 && $0.last?.isoWeekday == 7 })
    }

    /// September 2026 starts on a Tuesday, so the first row is padded with 31 August.
    @Test func theFirstRowHoldsTheMondayOfTheWeekTheMonthStartsIn() {
        let grid = MonthGrid(year: 2026, month: 9)
        #expect(grid.weeks[0][0] == Day(year: 2026, month: 8, day: 31))
        #expect(grid.weeks[0][1] == Day(year: 2026, month: 9, day: 1))
    }

    @Test func daysRunWithoutAGapAndCoverTheWholeMonth() {
        let grid = MonthGrid(year: 2026, month: 9)
        let days = grid.weeks.flatMap { $0 }
        #expect(days.count == 42)
        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(later == earlier.adding(days: 1))
        }
        #expect(days.contains(Day(year: 2026, month: 9, day: 1)))
        #expect(days.contains(Day(year: 2026, month: 9, day: 30)))
    }

    /// The padding is what `foreground`/`contains` dims — it must not read as part of the month.
    @Test func containsOnlyTheDaysOfItsOwnMonth() {
        let grid = MonthGrid(year: 2026, month: 9)
        #expect(grid.contains(Day(year: 2026, month: 9, day: 25)))
        #expect(!grid.contains(Day(year: 2026, month: 8, day: 31)))
        #expect(!grid.contains(Day(year: 2026, month: 10, day: 1)))
        #expect(!grid.contains(Day(year: 2025, month: 9, day: 25)))
    }

    /// A February that starts on a Monday (2027) is the shortest possible grid: without the fixed
    /// six rows it would be four, and the popover would change height as you page through months.
    @Test func everyMonthGetsSixRowsEvenTheShortest() {
        let february = MonthGrid(year: 2027, month: 2)
        #expect(february.weeks[0][0] == Day(year: 2027, month: 2, day: 1))
        #expect(february.weeks.count == 6)
    }

    @Test func steppingCrossesTheYearBoundary() {
        let january = MonthGrid(year: 2026, month: 1)
        #expect(january.previous == MonthGrid(year: 2025, month: 12))
        let december = MonthGrid(year: 2026, month: 12)
        #expect(december.next == MonthGrid(year: 2027, month: 1))
    }

    /// Break-proof: month 0 / 13 are how `previous` and `next` express the boundary, so a grid
    /// built from them must normalise rather than produce a month outside 1…12.
    @Test func monthsOutsideOneToTwelveNormalise() {
        #expect(MonthGrid(year: 2026, month: 0).month == 12)
        #expect(MonthGrid(year: 2026, month: 0).year == 2025)
        #expect(MonthGrid(year: 2026, month: 13).month == 1)
        #expect(MonthGrid(year: 2026, month: 13).year == 2027)
        #expect(MonthGrid(year: 2026, month: -11) == MonthGrid(year: 2025, month: 1))
        #expect(MonthGrid(year: 2026, month: 25) == MonthGrid(year: 2028, month: 1))
    }

    @Test func aGridOpensOnTheMonthOfTheDayItIsBuiltFrom() {
        let grid = MonthGrid(containing: Day(year: 2026, month: 12, day: 31))
        #expect(grid.year == 2026)
        #expect(grid.month == 12)
    }

    @Test func theHeaderNamesTheMonthAndYear() {
        #expect(MonthGrid(year: 2026, month: 9).title == "Sep 2026")
        #expect(MonthGrid(year: 2026, month: 9).spelledTitle == "September 2026")
    }

    @Test func weekdayHeadingsStartOnMonday() {
        #expect(MonthGrid.weekdayInitials == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
    }

    /// STYLEGUIDE §8 — VoiceOver reads a day cell in full words, with `today`/`tomorrow` named.
    @Test func aDayCellIsSpokenInFullWords() {
        let today = Day(year: 2026, month: 9, day: 24)
        #expect(Copy.dayPickerCell(Day(year: 2026, month: 9, day: 25), today: today)
            == "25 September 2026, tomorrow")
        #expect(Copy.dayPickerCell(today, today: today) == "24 September 2026, today")
        #expect(Copy.dayPickerCell(Day(year: 2026, month: 10, day: 5), today: today)
            == "5 October 2026")
    }
}
