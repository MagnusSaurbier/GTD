import Testing
import Foundation
import GTDModel

struct DayTests {

    @Test func isoRoundTrip() {
        for serial in stride(from: -20000, through: 30000, by: 137) {
            let day = Day(serial: serial)
            #expect(Day(iso: day.iso) == day)
            #expect(day.serial == serial)
        }
    }

    @Test func knownDates() {
        #expect(Day(year: 1970, month: 1, day: 1).serial == 0)
        #expect(Day(year: 2026, month: 9, day: 19).iso == "2026-09-19")
        // 2026-09-19 is a Saturday.
        #expect(Day(year: 2026, month: 9, day: 19).isoWeekday == 6)
        #expect(Day(year: 1970, month: 1, day: 1).isoWeekday == 4)   // Thursday
    }

    @Test func leapYears() {
        #expect(Day(year: 2024, month: 2, day: 28).adding(days: 1) == Day(year: 2024, month: 2, day: 29))
        #expect(Day(year: 2100, month: 2, day: 28).adding(days: 1) == Day(year: 2100, month: 3, day: 1))
        #expect(Day(year: 2000, month: 2, day: 28).adding(days: 1) == Day(year: 2000, month: 2, day: 29))
    }

    @Test func differences() {
        let a = Day(year: 2026, month: 1, day: 1)
        #expect(a.adding(days: 365).days(since: a) == 365)
        #expect(a.days(since: a.adding(days: 3)) == -3)
    }

    @Test func isoWeekNumbers() {
        // 2026-01-01 is a Thursday, so it belongs to week 1 of 2026.
        #expect(Day(year: 2026, month: 1, day: 1).isoWeek == (2026, 1))
        // 2027-01-01 is a Friday, so it still belongs to week 53 of 2026.
        #expect(Day(year: 2027, month: 1, day: 1).isoWeek.year == 2026)
        #expect(Day(year: 2026, month: 9, day: 19).isoWeek == (2026, 38))
        #expect(Day(year: 2026, month: 9, day: 14).startOfISOWeek == Day(year: 2026, month: 9, day: 14))
    }

    @Test func parsingTolerance() {
        #expect(Day(iso: "2026-09-19T08:00:00+02:00") == Day(year: 2026, month: 9, day: 19))
        #expect(Day(iso: "not a date") == nil)
        #expect(Day(iso: "2026-13-01") == nil)
    }

    @Test func dayTimeParsing() {
        #expect(DayTime(hhmm: "07:00")?.hhmm == "07:00")
        #expect(DayTime(hhmm: "22:30:00")?.minutesSinceMidnight == 22 * 60 + 30)
        #expect(DayTime(hhmm: "25:00") == nil)
    }

    @Test func timeBuckets() {
        #expect(TimeBucket(minutes: nil) == nil)
        #expect(TimeBucket(minutes: 0) == nil)        // `timeEstimate: 0` is never a bucket
        #expect(TimeBucket(minutes: 10) == .upTo10)
        #expect(TimeBucket(minutes: 45) == .upTo60)
        #expect(TimeBucket(minutes: 240) == .over60)
        #expect(TimeBucket.upTo30.minutes == 30)
        #expect(TimeBucket.upTo30.fits(available: 30))
        #expect(!TimeBucket.upTo60.fits(available: 30))
    }

    @Test func noteIDParts() {
        let id = NoteID(path: "Projects/Applications/DAAD/DAAD.md")
        #expect(id.title == "DAAD")
        #expect(id.folder == "Projects/Applications/DAAD")
        #expect(id.isInside("Projects"))
        #expect(!id.isInside("Actions"))
        #expect(NoteID(path: "/Actions//A.md/").path == "Actions/A.md")
    }

    @Test func checkboxScan() {
        let boxes = Checkbox.scan("- [ ] one\n  - [x] two\ntext\n* [ ] three\n-[ ] not a box")
        #expect(boxes == [
            Checkbox(text: "one", done: false),
            Checkbox(text: "two", done: true),
            Checkbox(text: "three", done: false),
        ])
    }

    @Test func checkboxScanNestedDepths() {
        // The user's "Read paper" note: tab-indented sub-steps under two parents.
        let what = "- [ ] Put paper into NotebookLM\n- [ ] ask for\n\t- [ ] Task at hand\n\t- [ ] contribution\n"
            + "- [ ] Read paper\n  - [ ] two spaces\n      - [ ] deeper\n  - [x] back to one\nprose\n- [ ] top"
        let nested = Checkbox.scanNested(what)
        #expect(nested.map(\.depth) == [0, 0, 1, 1, 0, 1, 2, 1, 0])
        #expect(nested.map(\.checkbox) == Checkbox.scan(what), "same order and count as scan — the toggle index")
    }
}
