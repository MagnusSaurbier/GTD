import Testing
import GTDModel

/// `Weekday` (a routine's `day:`) and `Routine.isScheduled(on:)`.
struct WeekdayTests {
    @Test func parsesFullNamesAndAbbreviationsCaseInsensitively() {
        #expect(Weekday(name: "Sunday") == .sunday)
        #expect(Weekday(name: "sunday") == .sunday)
        #expect(Weekday(name: " MONDAY ") == .monday)
        #expect(Weekday(name: "Wed") == .wednesday)
        #expect(Weekday(name: "sat") == .saturday)
    }

    @Test func refusesAnythingElse() {
        #expect(Weekday(name: "Someday") == nil)
        #expect(Weekday(name: "Su") == nil)
        #expect(Weekday(name: "Sonntag") == nil)
        #expect(Weekday(name: "7") == nil)
        #expect(Weekday(name: "") == nil)
    }

    @Test func namesRoundTrip() {
        for weekday in Weekday.allCases { #expect(Weekday(name: weekday.name) == weekday) }
    }

    @Test func gregorianNumberingStartsOnSunday() {
        #expect(Weekday.sunday.gregorianWeekday == 1)
        #expect(Weekday.monday.gregorianWeekday == 2)
        #expect(Weekday.saturday.gregorianWeekday == 7)
    }

    @Test func dayKnowsItsWeekday() {
        #expect(Day(year: 2026, month: 9, day: 27).weekday == .sunday)
        #expect(Day(year: 2026, month: 9, day: 28).weekday == .monday)
    }

    @Test func aRoutineWithoutADayIsScheduledEveryDay() {
        let routine = Routine(id: NoteID(path: "GTD/Routines/Morning.md"), title: "Morning")
        let monday = Day(year: 2026, month: 9, day: 28)
        for offset in 0..<7 { #expect(routine.isScheduled(on: monday.adding(days: offset))) }
    }

    @Test func aRoutineWithADayIsScheduledOnlyOnThatWeekday() {
        let routine = Routine(
            id: NoteID(path: "GTD/Routines/Topic Probe Research.md"), title: "Topic Probe Research",
            time: DayTime(hour: 9, minute: 0), day: .sunday)
        let monday = Day(year: 2026, month: 9, day: 28)
        let scheduled = (0..<7).map { monday.adding(days: $0) }.filter { routine.isScheduled(on: $0) }
        #expect(scheduled == [Day(year: 2026, month: 10, day: 4)])
    }
}
