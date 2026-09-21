import Testing
import Foundation
import GTDModel
@testable import GTDStats

/// `RoutineAudit.compute` — the 7-day heatmap, template-drift handling, multi-device log
/// merging and the trend-vs-previous-week number.
struct RoutineAuditTests {

    static let end = Day(year: 2026, month: 9, day: 20)   // a Sunday; window is Sep 14…20

    static func entry(
        _ dayOffset: Int, routine: String, step: String,
        result: RoutineStepResult, hour: Int = 8, device: String = "iPhone"
    ) -> RoutineLogEntry {
        RoutineLogEntry(
            day: end.adding(days: -6 + dayOffset), routine: routine, step: step, result: result,
            at: Date(timeIntervalSince1970: Double(dayOffset * 86_400 + hour * 3600)), device: device)
    }

    static func routine(_ title: String, steps: [String]) -> Routine {
        Routine(
            id: NoteID(path: "GTD/Routines/\(title).md"), title: title,
            steps: steps.map { RoutineStep(id: RoutineStep.slug($0), title: $0) })
    }

    // MARK: Empty data

    @Test func noRoutinesProducesNoAudits() {
        #expect(RoutineAudit.compute(routines: [], log: [], endingOn: Self.end).isEmpty)
    }

    @Test func routineWithNoLogEntriesIsAllNotLoggedAndZeroPercent() {
        let morning = Self.routine("Morning", steps: ["Wake up", "Drink water"])
        let audits = RoutineAudit.compute(routines: [morning], log: [], endingOn: Self.end)
        #expect(audits.count == 1)
        let audit = audits[0]
        #expect(audit.rows.count == 2)
        #expect(audit.rows.allSatisfy { row in row.cells.allSatisfy { $0.result == nil } })
        #expect(audit.completionPercent == 0)
        #expect(audit.trend == 0)
    }

    // MARK: Grid shape and per-step completion

    @Test func gridIsSevenDaysWideEndingOnTheRequestedDay() {
        let morning = Self.routine("Morning", steps: ["Wake up"])
        let log = [Self.entry(6, routine: "Morning", step: "wake-up", result: .done)]   // last day
        let audit = RoutineAudit.compute(routines: [morning], log: log, endingOn: Self.end)[0]
        let row = audit.rows[0]
        #expect(row.cells.count == 7)
        #expect(row.cells.first?.day == Self.end.adding(days: -6))
        #expect(row.cells.last?.day == Self.end)
        #expect(row.cells.last?.result == .done)
        #expect(row.completionPercent == 14)   // 1/7 rounded
    }

    @Test func skippedCountsAsLoggedButNotAsCompletion() {
        let bedtime = Self.routine("Bedtime", steps: ["Brush teeth"])
        let log = [Self.entry(0, routine: "Bedtime", step: "brush-teeth", result: .skipped)]
        let audit = RoutineAudit.compute(routines: [bedtime], log: log, endingOn: Self.end)[0]
        #expect(audit.rows[0].cells[0].result == .skipped)
        #expect(audit.rows[0].completionPercent == 0)
    }

    @Test func routineCompletionPercentAveragesAllStepCells() {
        let morning = Self.routine("Morning", steps: ["A", "B"])
        // 7 done for step A, 0 for step B ⇒ 7 / 14 = 50%.
        let log = (0..<7).map { Self.entry($0, routine: "Morning", step: "a", result: .done) }
        let audit = RoutineAudit.compute(routines: [morning], log: log, endingOn: Self.end)[0]
        #expect(audit.rows.first { $0.stepID == "a" }?.completionPercent == 100)
        #expect(audit.rows.first { $0.stepID == "b" }?.completionPercent == 0)
        #expect(audit.completionPercent == 50)
    }

    // MARK: Template drift

    @Test func stepsRemovedFromTheTemplateAreDroppedEvenIfLogged() {
        let morning = Self.routine("Morning", steps: ["Wake up"])   // "Old step" no longer templated
        let log = [Self.entry(0, routine: "Morning", step: "old-step", result: .done)]
        let audit = RoutineAudit.compute(routines: [morning], log: log, endingOn: Self.end)[0]
        #expect(audit.rows.map(\.stepID) == ["wake-up"])
    }

    @Test func newTemplateStepsShowNotLoggedForDaysBeforeTheyExisted() {
        let morning = Self.routine("Morning", steps: ["Brand new step"])
        let audit = RoutineAudit.compute(routines: [morning], log: [], endingOn: Self.end)[0]
        #expect(audit.rows[0].cells.allSatisfy { $0.result == nil })
    }

    // MARK: Multi-device merge

    @Test func laterDeviceEntryWinsForTheSameCell() {
        let morning = Self.routine("Morning", steps: ["Wake up"])
        let log = [
            Self.entry(0, routine: "Morning", step: "wake-up", result: .skipped, hour: 7, device: "iPhone"),
            Self.entry(0, routine: "Morning", step: "wake-up", result: .done, hour: 20, device: "Mac"),
        ]
        let audit = RoutineAudit.compute(routines: [morning], log: log, endingOn: Self.end)[0]
        #expect(audit.rows[0].cells[0].result == .done)
    }

    @Test func entriesForOtherRoutinesAreIgnored() {
        let morning = Self.routine("Morning", steps: ["Wake up"])
        let log = [Self.entry(0, routine: "Bedtime", step: "wake-up", result: .done)]
        let audit = RoutineAudit.compute(routines: [morning], log: log, endingOn: Self.end)[0]
        #expect(audit.rows[0].cells[0].result == nil)
    }

    // MARK: Trend

    @Test func trendComparesAgainstThePriorSevenDays() {
        let morning = Self.routine("Morning", steps: ["Wake up"])
        // Previous window (days -13…-7 from `end`, offsets via a second `entry` helper below):
        // 7/7 done. Current window: 0/7 done. Trend should be -100.
        let previousWeekEntries = (0..<7).map { offset -> RoutineLogEntry in
            RoutineLogEntry(
                day: Self.end.adding(days: -13 + offset), routine: "Morning", step: "wake-up",
                result: .done, at: Date(timeIntervalSince1970: Double(offset)), device: "iPhone")
        }
        let audit = RoutineAudit.compute(routines: [morning], log: previousWeekEntries, endingOn: Self.end)[0]
        #expect(audit.completionPercent == 0)
        #expect(audit.trend == -100)
    }

    @Test func multipleRoutinesEachGetTheirOwnAudit() {
        let morning = Self.routine("Morning", steps: ["Wake up"])
        let bedtime = Self.routine("Bedtime", steps: ["Brush teeth"])
        let log = [Self.entry(0, routine: "Morning", step: "wake-up", result: .done)]
        let audits = RoutineAudit.compute(routines: [morning, bedtime], log: log, endingOn: Self.end)
        #expect(audits.count == 2)
        #expect(audits.first { $0.title == "Morning" }?.rows[0].cells[0].result == .done)
        #expect(audits.first { $0.title == "Bedtime" }?.rows[0].cells.allSatisfy { $0.result == nil } == true)
    }
}
