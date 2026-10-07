import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
import DesignSystem
@testable import FeatureWaiting

/// `WaitingListModel` — staleness ordering, deferrals, timeline bucketing (across month and
/// year boundaries), overdue detection and the calendar-strip signal mapping. Linux-testable,
/// fixtures with a fixed `today` throughout (T23).
@MainActor
struct FeatureWaitingTests {

    // MARK: - Test helpers

    private func makeAction(
        _ title: String,
        status: ActionStatus,
        who: String? = nil,
        followUp: Day? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        created: Date? = nil,
        modified: Date? = nil
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"),
            title: title,
            status: status,
            deferDate: deferDate,
            due: due,
            waitingFor: who,
            followUpDate: followUp,
            created: created,
            modified: modified)
    }

    private func makeList(actions: [Action], today: Day) -> WaitingListModel {
        let snapshot = VaultSnapshot(actions: actions)
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot),
            snapshot: snapshot,
            today: { today })
        return WaitingListModel(model: model)
    }

    // MARK: - Waiting list: staleness ordering (W2)

    @Test func waitingListSortedByStalenessLongestOverdueFirst() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("Enrolment certificate", status: .waiting, who: "Office", followUp: today.adding(days: 6)),
            makeAction("Reference letter", status: .waiting, who: "Prof. Weber", followUp: today.adding(days: -9)),
            makeAction("Deposit refund", status: .waiting, who: "Landlord", followUp: today.adding(days: 1)),
            makeAction("No follow-up yet", status: .waiting, who: "Someone", followUp: nil),
        ], today: today)

        let order = list.waiting.map(\.title)
        #expect(order == [
            "Reference letter",   // -9d, most overdue
            "Deposit refund",     // +1d
            "Enrolment certificate", // +6d
            "No follow-up yet",   // no date sorts last
        ])
    }

    @Test func waitingListExcludesNonWaitingActions() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("Waiting item", status: .waiting, who: "X", followUp: today),
            makeAction("Next item", status: .next),
            makeAction("Done item", status: .done),
        ], today: today)
        #expect(list.waiting.map(\.title) == ["Waiting item"])
    }

    // MARK: - Overdue detection

    @Test func isOverdueWhenFollowUpHasPassedOrIsToday() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        let overdueYesterday = makeAction("A", status: .waiting, who: "X", followUp: today.adding(days: -1))
        let dueToday = makeAction("B", status: .waiting, who: "X", followUp: today)
        let dueTomorrow = makeAction("C", status: .waiting, who: "X", followUp: today.adding(days: 1))
        let noFollowUp = makeAction("D", status: .waiting, who: "X", followUp: nil)

        #expect(list.isOverdue(overdueYesterday))
        #expect(list.isOverdue(dueToday))
        #expect(!list.isOverdue(dueTomorrow))
        #expect(!list.isOverdue(noFollowUp))
    }

    // MARK: - "Waiting since N days"

    @Test func waitingSinceDaysPrefersModifiedOverCreated() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        let modifiedFiveDaysAgo = makeAction(
            "A", status: .waiting, who: "X", followUp: today,
            created: Fixtures.date(today.adding(days: -20), 9, 0),
            modified: Fixtures.date(today.adding(days: -5), 9, 0))
        #expect(list.waitingSinceDays(modifiedFiveDaysAgo) == 5)

        let createdOnlyTenDaysAgo = makeAction(
            "B", status: .waiting, who: "X", followUp: today,
            created: Fixtures.date(today.adding(days: -10), 9, 0),
            modified: nil)
        #expect(list.waitingSinceDays(createdOnlyTenDaysAgo) == 10)

        let neitherStamped = makeAction("C", status: .waiting, who: "X", followUp: today)
        #expect(list.waitingSinceDays(neitherStamped) == 0)
    }

    // MARK: - Row meta text (W1/D39 — who is optional)

    /// `<who> · <age>` when `who` is on file, plain `<age>` when it is empty/nil — never a
    /// dangling separator (STYLEGUIDE "no lying defaults": an absent value is omitted, not
    /// printed as an empty dash).
    @Test func rowMetaNamesWhoWhenPresentAndOmitsItWhenNot() {
        #expect(WaitingListModel.rowMeta(who: "Finanzamt", ageText: "16d") == ["Finanzamt", "16d"])
        #expect(WaitingListModel.rowMeta(who: "", ageText: "16d") == ["16d"])
        #expect(WaitingListModel.rowMeta(who: nil, ageText: "16d") == ["16d"])
    }

    @Test func metaPartsForActionCombinesWaitingForAndTheComputedAge() {
        let today = Day(year: 2026, month: 9, day: 19)
        let withWho = makeAction(
            "A", status: .waiting, who: "Finanzamt", followUp: today,
            created: Fixtures.date(today.adding(days: -16), 9, 0))
        let withoutWho = makeAction(
            "B", status: .waiting, who: nil, followUp: today,
            created: Fixtures.date(today.adding(days: -16), 9, 0))
        let list = makeList(actions: [withWho, withoutWho], today: today)

        #expect(list.metaParts(for: withWho) == ["Finanzamt", "16d"])
        #expect(list.metaParts(for: withoutWho) == ["16d"])
    }

    // MARK: - Editing / bumping who and follow-up

    @Test func waitingInfoReflectsTheCurrentWhoAndFollowUp() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        let action = makeAction("A", status: .waiting, who: "Alice", followUp: today.adding(days: 3))
        #expect(list.waitingInfo(for: action) == WaitingInfo(who: "Alice", followUp: today.adding(days: 3)))

        // W1/D39 — who is optional: the follow-up date alone is a complete wait.
        let anonymous = makeAction("B", status: .waiting, who: nil, followUp: today)
        #expect(list.waitingInfo(for: anonymous) == WaitingInfo(who: nil, followUp: today))
    }

    @Test func bumpedKeepsWhoAndSetsTheNewFollowUpDate() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        let action = makeAction("A", status: .waiting, who: "Alice", followUp: today.adding(days: -9))
        let bumped = list.bumped(action, to: today.adding(days: 7))
        #expect(bumped == WaitingInfo(who: "Alice", followUp: today.adding(days: 7)))

        // W1/D39 — the who is optional, so an item without one still bumps. This returned `nil`
        // until 2026-09-24 and the row's calendar then dropped the date the user had picked: on a
        // real vault, where M2 imported every waiting item without a who, no follow-up date could
        // be set from the list at all.
        let noWho = makeAction("B", status: .waiting, who: nil, followUp: today)
        #expect(list.bumped(noWho, to: today.adding(days: 7))
            == WaitingInfo(who: nil, followUp: today.adding(days: 7)))

        // A blank who is normalised away — never an empty `waitingFor:` line (§1).
        let blankWho = makeAction("C", status: .waiting, who: "  ", followUp: today)
        #expect(list.bumped(blankWho, to: today.adding(days: 7)).who == nil)
    }

    @Test func suggestedBumpIsSevenDaysFromToday() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        #expect(list.suggestedBump == today.adding(days: 7))
    }

    // MARK: - Deferrals (#86)

    /// A deferral is a who-less waiting item: listed with the others until its date, gone from
    /// the list once it is back in Next.
    @Test func deferralsWaitHereUntilTheyAreBack() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("Tomorrow", status: .waiting, followUp: today.adding(days: 1)),
            makeAction("A month out", status: .waiting, followUp: today.adding(days: 30)),
            makeAction("Already back", status: .waiting, followUp: today),
            makeAction("Chase", status: .waiting, who: "Lena", followUp: today.adding(days: -1)),
        ], today: today)
        #expect(list.waiting.map(\.title) == ["Chase", "Tomorrow", "A month out"])
        #expect(list.metaParts(for: list.waiting[1]).count == 1)   // no who, no dangling separator
    }

    // MARK: - Timeline bucketing across a month boundary (D3)

    @Test func timelineBucketsCorrectlyAcrossAMonthBoundary() {
        let today = Day(year: 2026, month: 1, day: 28)
        let list = makeList(actions: [
            makeAction("End of January", status: .next, due: Day(year: 2026, month: 1, day: 31)),
            makeAction("Start of February", status: .next, due: Day(year: 2026, month: 2, day: 1)),
            makeAction("A few days into February", status: .next, due: Day(year: 2026, month: 2, day: 5)),
        ], today: today)

        let columns = list.timeline(days: 14)
        #expect(columns.count == 14)
        #expect(columns.first?.day == today)
        #expect(columns.last?.day == Day(year: 2026, month: 2, day: 10))

        func titles(on day: Day) -> [String] {
            columns.first { $0.day == day }?.entries.map(\.title) ?? []
        }
        #expect(titles(on: Day(year: 2026, month: 1, day: 31)) == ["End of January"])
        #expect(titles(on: Day(year: 2026, month: 2, day: 1)) == ["Start of February"])
        #expect(titles(on: Day(year: 2026, month: 2, day: 5)) == ["A few days into February"])
    }

    // MARK: - Timeline bucketing across a year boundary (D3)

    @Test func timelineBucketsCorrectlyAcrossAYearBoundary() {
        let today = Day(year: 2026, month: 12, day: 28)
        let list = makeList(actions: [
            makeAction("End of 2026", status: .next, due: Day(year: 2026, month: 12, day: 31)),
            makeAction("Start of 2027", status: .next, due: Day(year: 2027, month: 1, day: 1)),
            makeAction("A week into 2027", status: .next, due: Day(year: 2027, month: 1, day: 4)),
        ], today: today)

        let columns = list.timeline(days: 14)
        #expect(columns.last?.day == Day(year: 2027, month: 1, day: 10))

        func titles(on day: Day) -> [String] {
            columns.first { $0.day == day }?.entries.map(\.title) ?? []
        }
        #expect(titles(on: Day(year: 2026, month: 12, day: 31)) == ["End of 2026"])
        #expect(titles(on: Day(year: 2027, month: 1, day: 1)) == ["Start of 2027"])
        #expect(titles(on: Day(year: 2027, month: 1, day: 4)) == ["A week into 2027"])
    }

    // MARK: - Overdue pile

    @Test func overduePileCollectsOnlyPastEntries() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("Overdue due date", status: .next, due: today.adding(days: -1)),
            makeAction("Due today (not in the pile)", status: .next, due: today),
            makeAction("Overdue follow-up", status: .waiting, who: "X", followUp: today.adding(days: -2)),
            makeAction("Stale deferral", status: .waiting, followUp: today.adding(days: -3)),
            makeAction("Future due date", status: .next, due: today.adding(days: 5)),
        ], today: today)

        let pile = list.overduePile
        let titles = Set(pile.map(\.title))
        #expect(titles == ["Overdue due date", "Overdue follow-up", "Stale deferral"])
        #expect(pile.allSatisfy { $0.day < today })

        let kinds = Dictionary(uniqueKeysWithValues: pile.map { ($0.title, $0.kind) })
        #expect(kinds["Overdue due date"] == .due)
        #expect(kinds["Overdue follow-up"] == .followUp)
        #expect(kinds["Stale deferral"] == .followUp)
    }

    // MARK: - Calendar-strip marker colour (STYLEGUIDE §2.2 / §3.10)

    @Test func signalStepForDueMarkers() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        func step(_ delta: Int) -> SignalStep? {
            list.signalStep(for: Rules.TimelineEntry(
                day: today.adding(days: delta), action: NoteID(path: "Actions/A.md"), title: "A", kind: .due))
        }
        #expect(step(-1) == .overdue)
        #expect(step(0) == .attention)
        #expect(step(3) == .aging)   // default dueSoonDays == 3
        #expect(step(4) == nil)
    }

    @Test func signalStepForFollowUpMarkers() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        func step(_ delta: Int) -> SignalStep? {
            list.signalStep(for: Rules.TimelineEntry(
                day: today.adding(days: delta), action: NoteID(path: "Actions/A.md"), title: "A", kind: .followUp))
        }
        #expect(step(-3) == .attention)
        #expect(step(0) == .attention)
        #expect(step(2) == .aging)   // default followUpSoonDays == 2
        #expect(step(5) == nil)
    }

    /// A deferral's marker (a who-less follow-up, #86) is never tinted: it is not a chase.
    @Test func deferralMarkersAreNeverTinted() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [makeAction("A", status: .waiting, followUp: today)], today: today)
        for delta in [-10, -1, 0, 1, 10] {
            let step = list.signalStep(for: Rules.TimelineEntry(
                day: today.adding(days: delta), action: NoteID(path: "Actions/A.md"), title: "A", kind: .followUp))
            #expect(step == nil)
        }
    }

    // MARK: - Recent-who suggestions

    @Test func recentWhoDedupesAndCapsAtFive() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("A", status: .waiting, who: "Alice", followUp: today.adding(days: -1)),
            makeAction("B", status: .waiting, who: "Bob", followUp: today.adding(days: -2)),
            makeAction("C", status: .waiting, who: "Alice", followUp: today.adding(days: 1)), // duplicate
            makeAction("D", status: .waiting, who: "Carol", followUp: today.adding(days: 2)),
            makeAction("E", status: .waiting, who: "Dave", followUp: today.adding(days: 3)),
            makeAction("F", status: .waiting, who: "Eve", followUp: today.adding(days: 4)),
            makeAction("G", status: .waiting, who: "Frank", followUp: today.adding(days: 5)),
        ], today: today)

        let who = list.recentWho
        #expect(who.count == 5)
        #expect(Set(who).count == who.count)   // no duplicates
        #expect(who == ["Bob", "Alice", "Carol", "Dave", "Eve"])   // in staleness order, first sighting wins
    }

    // MARK: - Badges delegate to Rules + SignalPresentation

    @Test func badgesReflectTheChaseSignalForAnOverdueWaitingItem() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [
            makeAction("Overdue chase", status: .waiting, who: "X", followUp: today.adding(days: -9)),
        ], today: today)
        let action = list.waiting[0]
        let badges = list.badges(for: action)
        #expect(!badges.isEmpty)
        #expect(badges.first?.step == .attention)
    }

    /// M10 — the follow-up date chip of a row in chase state takes the chase signal's colour;
    /// a date still ahead (or no date) stays a plain chip.
    @Test func followUpChipIsTintedOnlyOnceTheDateHasPassed() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        let passed = makeAction("A", status: .waiting, who: "X", followUp: today.adding(days: -9))
        let ahead = makeAction("B", status: .waiting, who: "X", followUp: today.adding(days: 3))
        let none = makeAction("C", status: .waiting, who: "X", followUp: nil)

        #expect(list.followUpSignal(for: passed) == .attention)
        #expect(list.followUpSignal(for: ahead) == nil)
        #expect(list.followUpSignal(for: none) == nil)
    }

    // MARK: - Empty snapshot

    @Test func emptySnapshotProducesEmptyLists() {
        let today = Day(year: 2026, month: 9, day: 19)
        let list = makeList(actions: [], today: today)
        #expect(list.waiting.isEmpty)
        #expect(list.overduePile.isEmpty)
        #expect(list.recentWho.isEmpty)
        #expect(list.timeline(days: 14).count == 14)
        #expect(list.timeline(days: 14).allSatisfy { $0.entries.isEmpty })
    }
}
