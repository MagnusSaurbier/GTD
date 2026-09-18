import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDNotifications

/// Builds tiny snapshots and calendars by hand (no `Fixtures.calendar`) so every test is
/// explicit about the `TimeZone` it exercises, per the brief.
private enum Support {
    static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func instant(_ day: Day, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
    }

    static func action(
        _ title: String,
        status: ActionStatus = .next,
        due: Day? = nil,
        deferDate: Day? = nil,
        waitingFor: String? = nil,
        followUpDate: Day? = nil
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"),
            title: title,
            status: status,
            deferDate: deferDate,
            due: due,
            waitingFor: waitingFor,
            followUpDate: followUpDate)
    }

    static func routine(_ title: String, time: DayTime) -> Routine {
        Routine(id: NoteID(path: "GTD/Routines/\(title).md"), title: title, time: time)
    }
}

struct NotificationPlannerTests {
    private let utc = Support.calendar(timeZone: TimeZone(identifier: "UTC")!)

    // MARK: - The sample vault, end to end

    /// Exercises the whole planner against `Fixtures.sampleSnapshot`: past dates dropped
    /// (Prof. Weber's follow-up, the DAAD info mail's due date, today's already-passed morning
    /// for Lena), three same-morning items collapsed into one summary, and both routines always
    /// included.
    @Test func sampleVaultPlanMatchesHandComputedSet() {
        let now = Fixtures.date(Fixtures.today, 10, 0)   // 10:00 — this morning's 08:00 is past.
        let planned = NotificationPlanner.plan(
            snapshot: Fixtures.sampleSnapshot, now: now, calendar: Fixtures.calendar)

        #expect(planned.count == 9)

        let routineIDs = Set(planned.filter { $0.kind == .routineStart }.map(\.id))
        #expect(routineIDs == [
            "routineStart:GTD/Routines/Morning.md", "routineStart:GTD/Routines/Bedtime.md",
        ])

        let day1 = Fixtures.day(1).iso
        guard let collapsed = planned.first(where: { $0.id == "summary:\(day1)" }) else {
            Issue.record("expected a collapsed summary on \(day1)")
            return
        }
        #expect(collapsed.kind == .summary)
        #expect(collapsed.body.contains("3"))

        let expectedSingles: Set<String> = [
            "dueApproaching:Actions/Return the library books.md:\(Fixtures.day(2).iso)",
            "dueApproaching:Actions/Write DAAD motivation letter.md:\(Fixtures.day(4).iso)",
            "dueApproaching:Actions/Write DAAD motivation letter.md:\(Fixtures.day(5).iso)",
            "followUp:Actions/Enrolment certificate from the office.md:\(Fixtures.day(6).iso)",
            "deferReturn:Actions/Write the tenant profile.md:\(Fixtures.day(9).iso)",
            "deferReturn:Actions/Plan the semester timetable.md:\(Fixtures.day(20).iso)",
        ]
        #expect(Set(planned.map(\.id)).isSuperset(of: expectedSingles))

        // Overdue, already past `now`: never planned.
        #expect(!planned.contains { $0.id.contains("Reference letter from Prof. Weber") })
        #expect(!planned.contains { $0.id.contains("Reply to the DAAD info mail") })
    }

    // MARK: - Past dates ignored

    @Test func pastDeferDueAndFollowUpAreNeverPlanned() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        let snapshot = VaultSnapshot(actions: [
            Support.action("Stale defer", deferDate: today.adding(days: -1)),
            Support.action("Stale due", due: today.adding(days: -5)),
            Support.action(
                "Stale waiting", status: .waiting,
                waitingFor: "Bob", followUpDate: today.adding(days: -2)),
            // Today's morning notification has already fired by 09:00.
            Support.action("Defers today but too late", deferDate: today),
        ])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        #expect(planned.isEmpty)
    }

    @Test func futureDatesArePlanned() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        let snapshot = VaultSnapshot(actions: [
            Support.action("Comes back tomorrow", deferDate: today.adding(days: 1)),
        ])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        #expect(planned.count == 1)
        #expect(planned[0].kind == .deferReturn)
        #expect(planned[0].fireDate > now)
    }

    // MARK: - Completed / trashed items

    @Test func doneAndTrashedActionsAreNeverPlannedEvenWithFutureDates() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        let future = today.adding(days: 3)
        let snapshot = VaultSnapshot(actions: [
            Support.action("Done with a due date", status: .done, due: future),
            Support.action(
                "Trashed but was waiting", status: .trash,
                waitingFor: "Bob", followUpDate: future),
        ])

        #expect(NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc).isEmpty)
    }

    // MARK: - Follow-up requires `waiting` status

    @Test func followUpOnlyFiresForWaitingActions() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        // followUpDate set but status isn't `waiting` — should not happen via the reducer, but
        // the planner must not trust stray data.
        let snapshot = VaultSnapshot(actions: [
            Support.action("Not actually waiting", status: .next, followUpDate: today.adding(days: 2)),
        ])
        #expect(NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc).isEmpty)
    }

    // MARK: - Collapse rule

    @Test func threeSameMorningItemsCollapseIntoOneSummary() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 6, 0, calendar: utc)
        let target = today.adding(days: 2)
        let snapshot = VaultSnapshot(actions: [
            Support.action("A back today", deferDate: target),
            Support.action("B due today", due: target),
            Support.action("C waiting", status: .waiting, waitingFor: "X", followUpDate: target),
        ])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        // "B due today" also produces a day-before notification the day before `target`.
        #expect(planned.count == 2)
        let summary = planned.first { $0.kind == .summary }
        #expect(summary != nil)
        #expect(summary?.id == "summary:\(target.iso)")
        #expect(summary?.body.contains("3") == true)
    }

    @Test func summaryCanBeDisabledToKeepItemsSeparate() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 6, 0, calendar: utc)
        let target = today.adding(days: 2)
        let snapshot = VaultSnapshot(actions: [
            Support.action("A back today", deferDate: target),
            Support.action("C waiting", status: .waiting, waitingFor: "X", followUpDate: target),
        ])
        var settings = DeviceNotificationSettings.default
        settings.enabledKinds.remove(.summary)

        let planned = NotificationPlanner.plan(
            snapshot: snapshot, now: now, calendar: utc, settings: settings)
        #expect(planned.count == 2)
        #expect(planned.allSatisfy { $0.kind != .summary })
    }

    // MARK: - Per-kind settings

    @Test func disabledKindsAreNeverPlanned() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 6, 0, calendar: utc)
        var settings = DeviceNotificationSettings.default
        settings.enabledKinds = [.dueApproaching]
        let snapshot = VaultSnapshot(actions: [
            Support.action("Deferred", deferDate: today.adding(days: 1)),
            Support.action("Due", due: today.adding(days: 3)),
            Support.action(
                "Waiting", status: .waiting, waitingFor: "X", followUpDate: today.adding(days: 1)),
        ])

        let planned = NotificationPlanner.plan(
            snapshot: snapshot, now: now, calendar: utc, settings: settings)
        #expect(planned.allSatisfy { $0.kind == .dueApproaching })
        #expect(!planned.isEmpty)
    }

    @Test func routinesCanBeDisabled() {
        var settings = DeviceNotificationSettings.default
        settings.enabledKinds.remove(.routineStart)
        let snapshot = VaultSnapshot(routines: [Support.routine("Morning", time: DayTime(hour: 7, minute: 0))])
        let planned = NotificationPlanner.plan(
            snapshot: snapshot, now: Date(), calendar: utc, settings: settings)
        #expect(planned.isEmpty)
    }

    // MARK: - Routine notifications repeat daily

    @Test func routineNotificationsRepeatDailyAtTheirOwnTime() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        let snapshot = VaultSnapshot(routines: [
            Support.routine("Morning", time: DayTime(hour: 7, minute: 0)),
        ])
        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        #expect(planned.count == 1)
        #expect(planned[0].repeatsDaily)
        let components = utc.dateComponents([.hour, .minute], from: planned[0].fireDate)
        #expect(components.hour == 7)
        #expect(components.minute == 0)
        #expect(planned[0].deepLink == "gtd://routine/GTD/Routines/Morning.md")
    }

    @Test func routineWithoutATimeIsNeverPlanned() {
        let snapshot = VaultSnapshot(routines: [
            Routine(id: NoteID(path: "GTD/Routines/Untimed.md"), title: "Untimed", time: nil),
        ])
        #expect(NotificationPlanner.plan(snapshot: snapshot, now: Date(), calendar: utc).isEmpty)
    }

    // MARK: - Identifier stability (idempotent re-planning)

    @Test func identifiersAreStableAcrossReplanning() {
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 9, 0, calendar: utc)
        let snapshot = VaultSnapshot(actions: [
            Support.action("Stable", deferDate: today.adding(days: 3)),
        ])
        let first = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        let laterNow = Support.instant(today, 9, 30, calendar: utc)
        let second = NotificationPlanner.plan(snapshot: snapshot, now: laterNow, calendar: utc)
        #expect(first.map(\.id) == second.map(\.id))
    }

    // MARK: - 64-request cap: routines first, then soonest first

    @Test func capsAt64WithRoutinesFirstThenSoonest() {
        let today = Day(year: 2026, month: 1, day: 1)
        let now = Support.instant(today, 0, 0, calendar: utc)
        let routines = (0..<5).map { Support.routine("Routine \($0)", time: DayTime(hour: 6, minute: $0)) }
        // Due dates 2, 4, 6, … so the day-before and the day-of never land on the same date
        // across different actions — 140 distinct single-item candidates, all soonest-first
        // orderable without any collapsing.
        let actions = (1...70).map { k in
            Support.action("Action \(k)", due: today.adding(days: 2 * k))
        }
        let snapshot = VaultSnapshot(actions: actions, routines: routines)

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: utc)
        #expect(planned.count == NotificationPlanner.maxPending)

        let firstFive = planned.prefix(5)
        #expect(firstFive.allSatisfy { $0.kind == .routineStart })

        let rest = Array(planned.dropFirst(5))
        #expect(rest.count == 59)
        #expect(rest.allSatisfy { $0.kind == .dueApproaching })
        // Strictly ascending: the soonest 59 of the 140 candidates, i.e. days 1…59.
        for (index, notification) in rest.enumerated() {
            let expectedDay = today.adding(days: index + 1)
            #expect(Day(notification.fireDate, calendar: utc) == expectedDay)
        }
        // The 60th-soonest candidate (day 60) must have been dropped by the cap.
        #expect(!planned.contains { Day($0.fireDate, calendar: utc) == today.adding(days: 60) })
    }

    // MARK: - DST / time zones (explicit `TimeZone`, not `.current`)

    /// US spring-forward: 2027-03-14 loses the 02:00–03:00 hour in `America/New_York`. The
    /// planner must go through `Day.date(at:in:)` (calendar arithmetic), not `addingTimeInterval`,
    /// so the gap between the day-before and day-of morning is 23h, not 24h.
    @Test func springForwardShortensTheDayByOneHour() {
        let newYork = Support.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let dstDay = Day(year: 2027, month: 3, day: 14)
        let now = Support.instant(Day(year: 2027, month: 3, day: 1), 0, 0, calendar: newYork)
        let snapshot = VaultSnapshot(actions: [Support.action("Spans DST", due: dstDay)])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: newYork)
        let dayBefore = planned.first { $0.id.hasSuffix(dstDay.adding(days: -1).iso) }
        let dayOf = planned.first { $0.id.hasSuffix(dstDay.iso) }
        #expect(dayBefore != nil)
        #expect(dayOf != nil)
        if let dayBefore, let dayOf {
            #expect(dayOf.fireDate.timeIntervalSince(dayBefore.fireDate) == 23 * 3600)
        }
    }

    /// US fall-back: 2027-11-07 gains the 01:00–02:00 hour back in `America/New_York`, so the
    /// same pair of mornings is 25h apart.
    @Test func fallBackLengthensTheDayByOneHour() {
        let newYork = Support.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let dstDay = Day(year: 2027, month: 11, day: 7)
        let now = Support.instant(Day(year: 2027, month: 10, day: 25), 0, 0, calendar: newYork)
        let snapshot = VaultSnapshot(actions: [Support.action("Spans DST", due: dstDay)])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: newYork)
        let dayBefore = planned.first { $0.id.hasSuffix(dstDay.adding(days: -1).iso) }
        let dayOf = planned.first { $0.id.hasSuffix(dstDay.iso) }
        #expect(dayBefore != nil)
        #expect(dayOf != nil)
        if let dayBefore, let dayOf {
            #expect(dayOf.fireDate.timeIntervalSince(dayBefore.fireDate) == 25 * 3600)
        }
    }

    /// A fixed non-DST offset (`Asia/Kolkata`, UTC+5:30) still resolves 08:00 local to the
    /// correct UTC instant — the planner must honour the calendar passed in, not `.current`.
    @Test func fixedHalfHourOffsetTimeZoneIsHonoured() {
        let kolkata = Support.calendar(timeZone: TimeZone(identifier: "Asia/Kolkata")!)
        let today = Day(year: 2026, month: 6, day: 15)
        let now = Support.instant(today, 0, 0, calendar: kolkata)
        let snapshot = VaultSnapshot(actions: [
            Support.action("Deferred", deferDate: today.adding(days: 1)),
        ])

        let planned = NotificationPlanner.plan(snapshot: snapshot, now: now, calendar: kolkata)
        #expect(planned.count == 1)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let utcComponents = utcCalendar.dateComponents([.hour, .minute], from: planned[0].fireDate)
        // 08:00 IST == 02:30 UTC.
        #expect(utcComponents.hour == 2)
        #expect(utcComponents.minute == 30)
    }
}
