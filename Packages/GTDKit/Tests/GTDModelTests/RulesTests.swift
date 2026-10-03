import Testing
import Foundation
import GTDModel
import GTDFixtures

/// The derived queries, against the realistic sample vault.
struct RulesTests {
    private var snapshot: VaultSnapshot { Fixtures.sampleSnapshot }
    private var today: Day { Fixtures.today }

    @Test func inboxQueueIsLIFOAndExcludesReviewDeferrals() {
        let queue = Rules.inboxQueue(snapshot)
        #expect(queue.allSatisfy { $0.reviewReason == nil })
        #expect(queue == queue.sorted { $0.created > $1.created })
        #expect(Rules.reviewDeferredInbox(snapshot).count == 1)
    }

    @Test func nextListPinsInProgressAndRespectsFilters() {
        let all = Rules.nextList(snapshot, today: today)
        #expect(all.count == snapshot.config.nextCap - 1)
        #expect(all.prefix(2).allSatisfy { $0.status == .inProgress })

        let errands = Rules.nextList(snapshot, contexts: ["errands"], today: today)
        #expect(!errands.isEmpty)
        #expect(errands.allSatisfy { $0.contexts.contains("errands") })

        // An undecided estimate is never filtered away (§1 "no lying defaults").
        let quick = Rules.nextList(snapshot, timeAvailable: 10, today: today)
        #expect(quick.allSatisfy { $0.timeEstimate == nil || $0.timeEstimate! <= 10 })
        #expect(quick.contains { $0.timeEstimate == nil })
    }

    /// E1 — the order is `in-progress`, then the nearest deadline, then the oldest capture.
    @Test func nextListOrdersByDeadlineThenAge() throws {
        let list = Rules.nextList(snapshot, today: today)
        let committed = list.filter { $0.status == .next }
        let dued = committed.filter { $0.due != nil }
        #expect(dued.map { $0.due! } == dued.map { $0.due! }.sorted())
        #expect(dued.first?.title == "Reply to the DAAD info mail")    // the overdue one
        let undated = committed.drop { $0.due != nil }
        #expect(undated.allSatisfy { $0.due == nil })
    }

    @Test func onTheGoListOnlyShowsOnTheGoContexts() {
        let allowed = Set(snapshot.config.onTheGoContexts)
        let list = Rules.onTheGoNextList(snapshot, today: today)
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { !Set($0.contexts).isDisjoint(with: allowed) })
        // A filter outside the on-the-go set can never widen it (E2).
        #expect(Rules.onTheGoNextList(snapshot, contexts: ["deep-work"], today: today).isEmpty)
        #expect(Rules.onTheGoNextList(snapshot, contexts: ["calls"], today: today)
                .allSatisfy { $0.contexts.contains("calls") })
    }

    @Test func chaseAndWaiting() {
        let chase = Rules.chaseItems(snapshot, today: today)
        #expect(chase.count == 1)
        #expect(chase.first?.waitingFor == "Prof. Weber")
        let waiting = Rules.waitingList(snapshot, today: today)
        #expect(waiting.count == 5)       // 3 with a who, 2 deferrals (#86)
        // W2 — sorted by staleness: the longest-overdue follow-up first.
        #expect(waiting.map { $0.followUpDate! } == waiting.map { $0.followUpDate! }.sorted())
        #expect(Rules.waitingSince(waiting[0], today: today, calendar: Fixtures.calendar) == 28)
    }

    @Test func stalledProjects() {
        let stalled = Rules.stalledProjects(snapshot, today: today)
        #expect(stalled.map(\.id) == [Fixtures.flatProject.id])
    }

    /// #86 — deferrals are who-less waiting items: listed under Waiting, never under Next,
    /// and holding no cap slot until their date.
    @Test func deferralsWaitInWaiting() {
        let deferrals = Rules.waitingList(snapshot, today: today).filter(\.isWhoLessWaiting)
        #expect(deferrals.count == 2)
        let next = Rules.nextList(snapshot, today: today).map(\.id)
        #expect(deferrals.allSatisfy { !next.contains($0.id) })
        #expect(deferrals.allSatisfy { !Rules.isBackInNext($0, today: today) })
    }

    @Test func sidebarCounts() {
        let counts = Rules.sidebarCounts(snapshot, today: today)
        #expect(counts.inbox == 5)
        #expect(counts.next == 14)
        #expect(counts.someday == 6)
        #expect(counts.waiting == 5)      // 2 of them deferrals (#86)
        #expect(counts.projects == 4)
        // E3 — every count matches the list its row opens.
        #expect(counts.next == Rules.nextList(snapshot, today: today).count)
        #expect(counts.waiting == Rules.waitingList(snapshot, today: today).count)
        #expect(counts.inbox == Rules.inboxQueue(snapshot).count)
        #expect(counts.someday == snapshot.actions.count { $0.status == .someday })
    }

    @Test func capSignalOnlyAppearsAtTheCap() {
        #expect(Rules.capSignal(snapshot, today: today) == nil)
        var full = snapshot
        full.config.nextCap = 14
        #expect(Rules.capSignal(full, today: today)?.step == .attention)
        #expect(Rules.capSignal(full, today: today)?.kind == .cap(count: 14, cap: 14))
        full.config.nextCap = 13
        #expect(Rules.capSignal(full, today: today)?.step == .overdue)
        #expect(Rules.isAtCap(full, today: today))
    }

    @Test func signalsFollowTheStyleGuideTable() throws {
        let overdue = try #require(snapshot.actions.first { $0.title == "Reply to the DAAD info mail" })
        #expect(Rules.signals(for: overdue, today: today).contains {
            $0.kind == .overdue(days: 2) && $0.step == .overdue
        })

        let dueSoon = try #require(snapshot.actions.first { $0.title == "Answer Lena about the WG viewing" })
        #expect(Rules.dueBadge(for: dueSoon, today: today)?.step == .aging)

        let chase = try #require(Rules.chaseItems(snapshot, today: today).first)
        #expect(Rules.signals(for: chase, today: today).contains {
            $0.kind == .chase(days: 9) && $0.step == .attention
        })

        let stale = try #require(snapshot.actions.first { $0.title == "Cancel the gym membership" })
        #expect(Rules.signals(for: stale, today: today).contains {
            $0.kind == .untouched(days: 35) && $0.step == .attention
        })

        let oldCapture = try #require(snapshot.inbox.last)
        #expect(Rules.signals(for: oldCapture, today: today).first?.step == .aging)
    }

    @Test func suggestsProjectAtTwoCheckboxes() throws {
        let multi = try #require(snapshot.actions.first { $0.checkboxes.count >= 2 })
        #expect(Rules.suggestsProject(multi))
        let single = try #require(snapshot.actions.first { $0.checkboxes.isEmpty })
        #expect(!Rules.suggestsProject(single))
    }

    @Test func timelineCoversDueAndFollowUpDeferralsIncluded() {
        let entries = Rules.timeline(snapshot, from: today, to: today.adding(days: 13))
        #expect(entries.contains { $0.kind == .due })
        #expect(entries.contains { $0.kind == .followUp })
        // A deferral's date is its follow-up date (#86).
        #expect(entries.contains { $0.kind == .followUp && $0.title == "Write the tenant profile" })
        #expect(entries.map(\.day) == entries.map(\.day).sorted())
        // Out of range is out of the strip, and closed actions never appear.
        #expect(entries.allSatisfy { $0.day >= today && $0.day <= today.adding(days: 13) })
        #expect(Rules.timeline(snapshot, from: today.adding(days: 5), to: today).isEmpty)
        let closed = Set(snapshot.actions.filter(\.status.isClosed).map(\.id))
        #expect(entries.allSatisfy { !closed.contains($0.action) })
    }

    @Test func projectRowsCarryActiveActionsAndStepCount() throws {
        let rows = Rules.projectRows(snapshot, today: today)
        #expect(rows.count == snapshot.projects.count)
        #expect(rows.map { $0.project.status == .active } == [true, true, true, true, false])
        let daad = try #require(rows.first { $0.project.id == Fixtures.daadProject.id })
        #expect(daad.activeActions.allSatisfy { $0.status.countsTowardCap })
        #expect(daad.remainingSteps == Fixtures.daadProject.openSteps.count)
        #expect(!daad.isStalled)
        let flat = try #require(rows.first { $0.project.id == Fixtures.flatProject.id })
        #expect(flat.isStalled)
    }

    /// R-6/P1 — the area-less projects come first, and no "No area" header is invented for them
    /// (that is `ProjectsListModel.sections`' job, and it renders them headerless).
    @Test func projectRowsListAreaLessProjectsFirst() {
        let rows = Rules.projectRows(snapshot, today: today)
        let firstWithArea = rows.firstIndex { $0.project.area != nil } ?? rows.count
        #expect(rows.prefix(firstWithArea).allSatisfy { $0.project.area == nil })
        #expect(rows.dropFirst(firstWithArea).allSatisfy { $0.project.area != nil })
        #expect(rows.first?.project.id == Fixtures.flatProject.id,
                "the vault's only area-less project heads the list")
        // Within each half the old order still holds: active first, then title.
        let withArea = rows.filter { $0.project.area != nil }
        #expect(withArea.map { $0.project.status == .active } == [true, true, true, false])
    }

    @Test func archiveCandidatesAreOldClosedNotes() {
        let candidates = Rules.archiveCandidates(snapshot, today: today, calendar: Fixtures.calendar)
        #expect(candidates.map(\.title) == ["Collect DAAD transcripts"])
        #expect(candidates.allSatisfy { $0.status.isClosed })
    }
}

/// STYLEGUIDE §2.2 row by row, plus the boundaries of every `StalenessPolicy` threshold.
/// The wording lives in `DesignSystem.SignalPresentation`; here only the semantics are checked.
struct SignalRuleTests {
    private let today = TestVault.today
    private let calendar = TestVault.calendar

    private func signals(_ action: Action) -> [Signal] {
        Rules.signals(for: action, today: today, calendar: calendar)
    }

    // due: within 3 days ⇒ aging, today ⇒ attention, passed ⇒ overdue
    @Test(arguments: [
        (-2, SignalStep.overdue), (-1, .overdue), (0, .attention),
        (1, .aging), (3, .aging),
    ])
    func dueSignals(offset: Int, step: SignalStep) throws {
        let action = TestVault.action("Fällig", .next, due: TestVault.day(offset), modified: 0)
        let signal = try #require(Rules.dueBadge(for: action, today: today, calendar: calendar))
        #expect(signal.step == step)
        switch offset {
        case ..<0: #expect(signal.kind == .overdue(days: -offset))
        case 0: #expect(signal.kind == .dueToday)
        default: #expect(signal.kind == .dueSoon(TestVault.day(offset)))
        }
    }

    @Test func aDueDateFurtherOutIsQuiet() {
        let action = TestVault.action("Fällig", .next, due: TestVault.day(4), modified: 0)
        #expect(Rules.dueBadge(for: action, today: today, calendar: calendar) == nil)
        #expect(signals(action).isEmpty)
    }

    // follow-up: passed ⇒ chase (attention), within 2 days ⇒ aging
    @Test(arguments: [
        (-9, SignalStep.attention), (0, .attention), (1, .aging), (2, .aging),
    ])
    func followUpSignals(offset: Int, step: SignalStep) throws {
        let action = TestVault.action(
            "Warten", .waiting, waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(offset)),
            modified: 0)
        let signal = try #require(signals(action).first)
        #expect(signal.step == step)
        if offset <= 0 {
            #expect(signal.kind == .chase(days: -offset))
        } else {
            #expect(signal.kind == .followUpSoon(TestVault.day(offset)))
        }
    }

    @Test func aFollowUpFurtherOutIsQuiet() {
        let action = TestVault.action(
            "Warten", .waiting, waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(3)), modified: 0)
        #expect(signals(action).isEmpty)
    }

    /// The follow-up signal belongs to `waiting` — a demoted item must not keep it.
    @Test func followUpSignalsOnlyApplyToWaiting() {
        var action = TestVault.action("Nicht mehr warten", .next, modified: 0)
        action.followUpDate = TestVault.day(-3)
        #expect(signals(action).isEmpty)
    }

    // untouched: > 14 d ⇒ aging, > 30 d ⇒ attention
    @Test(arguments: [(14, false), (15, true), (30, true), (31, true)])
    func untouchedSignals(age: Int, hasSignal: Bool) {
        let action = TestVault.action("Alt", .next, modified: -age)
        let untouched = signals(action).first { if case .untouched = $0.kind { return true } else { return false } }
        #expect((untouched != nil) == hasSignal)
        if let untouched {
            #expect(untouched.kind == .untouched(days: age))
            #expect(untouched.step == (age > 30 ? .attention : .aging))
        }
    }

    /// A5 — a closed action shows nothing anywhere, so it carries no signals either.
    @Test(arguments: [ActionStatus.done, .legacyTrashed])
    func closedActionsAreSilent(status: ActionStatus) {
        let action = TestVault.action("Erledigt", status, due: TestVault.day(-5), modified: -90, completed: -1)
        #expect(signals(action).isEmpty)
    }

    // D1/#86 — `back` on the day a deferral (who-less waiting) returns, and only then; it is
    // never a `chase` item.
    @Test(arguments: [(0, true), (-1, false), (-5, false)])
    func returnedFromDefer(offset: Int, hasBadge: Bool) {
        let action = TestVault.action(
            "Zurück", .waiting, waiting: WaitingInfo(followUp: TestVault.day(offset)), modified: 0)
        let badge = Rules.returnedFromDeferBadge(for: action, today: today, calendar: calendar)
        #expect((badge != nil) == hasBadge)
        #expect(badge?.step == (hasBadge ? .neutral : nil))
        #expect(!signals(action).contains { if case .chase = $0.kind { true } else { false } })
    }

    @Test func aFutureDeferralCarriesNoBadge() {
        let action = TestVault.action(
            "Später", .waiting, waiting: WaitingInfo(followUp: TestVault.day(3)), modified: 0)
        #expect(Rules.returnedFromDeferBadge(for: action, today: today, calendar: calendar) == nil)
    }

    /// #86 — a waiting item **with** a who never comes back by itself: it is a `chase`.
    @Test func aWaitingItemWithAWhoIsAChaseNotABack() {
        let action = TestVault.action(
            "Warten", .waiting, waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(0)), modified: 0)
        #expect(Rules.returnedFromDeferBadge(for: action, today: today, calendar: calendar) == nil)
        #expect(signals(action).contains { $0.kind == .chase(days: 0) })
        #expect(!Rules.isBackInNext(action, today: today))
    }

    // inbox: older than 7 days ⇒ aging
    @Test(arguments: [(7, false), (8, true), (30, true)])
    func inboxAge(age: Int, hasSignal: Bool) {
        let item = TestVault.inboxItem("alt", created: -age)
        let signals = Rules.signals(for: item, today: today, calendar: calendar)
        #expect((signals.first != nil) == hasSignal)
        if let signal = signals.first {
            #expect(signal.kind == .inboxAge(days: age))
            #expect(signal.step == .aging)
        }
    }

    @Test func stalledIsTheOnlyProjectSignal() {
        let project = TestVault.project("Wohnungssuche")
        let empty = TestVault.snapshot(projects: [project])
        #expect(Rules.signals(for: project, in: empty, today: today) == [Signal(kind: .stalled, step: .attention)])

        // A Someday action is not a commitment, so the project stays stalled (P4).
        let parked = TestVault.snapshot(
            actions: [TestVault.action("Profil schreiben", .someday, project: project.id)],
            projects: [project])
        #expect(Rules.signals(for: project, in: parked, today: today)
                == [Signal(kind: .stalled, step: .attention)])

        let busy = TestVault.snapshot(
            actions: [TestVault.action("Profil schreiben", .next, project: project.id)],
            projects: [project])
        #expect(Rules.signals(for: project, in: busy, today: today).isEmpty)
    }

    /// P4 — `someday` actions are not commitments, so they leave a project stalled.
    /// The `someday` row replaces the old second-tier exception: the merged tier is not a
    /// commitment either, so an active project whose only action is Someday is stalled
    /// (ARCHITECTURE §6).
    @Test(arguments: [
        (ActionStatus.next, false), (.inProgress, false), (.waiting, false),
        (.someday, true), (.done, true), (.legacyTrashed, true),
    ])
    func whichActionsKeepAProjectAlive(status: ActionStatus, stalled: Bool) {
        let project = TestVault.project("Wohnungssuche")
        let action = TestVault.action(
            "Profil", status,
            project: project.id,
            waiting: status == .waiting ? WaitingInfo(who: "Lena", followUp: TestVault.day(3)) : nil,
            completed: status.isClosed ? -1 : nil)
        let vault = TestVault.snapshot(actions: [action], projects: [project])
        #expect(Rules.isStalled(project, in: vault, today: today) == stalled)
    }

    /// #86 — a deferral is a waiting item, and waiting keeps a project off the stalled list
    /// (before #86 a deferred action was hidden and left its project stalled).
    @Test func aDeferralKeepsItsProjectAlive() {
        let project = TestVault.project("Wohnungssuche")
        let vault = TestVault.snapshot(
            actions: [TestVault.action(
                "Profil", .waiting, project: project.id, waiting: WaitingInfo(followUp: TestVault.day(9)))],
            projects: [project])
        #expect(!Rules.isStalled(project, in: vault, today: today))
    }

    @Test func onlyActiveProjectsCanStall() {
        for status in [ProjectStatus.onHold, .someday, .done] {
            let project = TestVault.project("Nebenjob", status: status)
            #expect(!Rules.isStalled(project, in: TestVault.snapshot(projects: [project]), today: today))
        }
    }

    /// Signals are ordered by step, highest first, and the order never depends on sort stability.
    @Test func signalsAreOrderedByStep() {
        let action = TestVault.action("Alles auf einmal", .waiting,
                                      due: TestVault.day(-1),
                                      waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(2)),
                                      modified: -40)
        let steps = signals(action).map(\.step)
        #expect(steps == steps.sorted(by: >))
        #expect(steps.first == .overdue)
    }

    // D1/#86 — a deferral waits in Waiting until the day it names, and is back in Next on
    // that day: listed there, holding a slot, gone from Waiting and from the chase section.
    @Test(arguments: [(-1, true), (0, true), (1, false)])
    func deferralReturnBoundary(offset: Int, back: Bool) {
        let action = TestVault.action(
            "Später", .waiting, waiting: WaitingInfo(followUp: TestVault.day(offset)))
        let vault = TestVault.snapshot(actions: [action])
        #expect(Rules.isVisible(action, today: today))
        #expect(Rules.isBackInNext(action, today: today) == back)
        #expect(Rules.effectiveStatus(action, today: today) == (back ? .next : .waiting))
        #expect(Rules.nextList(vault, today: today).count == (back ? 1 : 0))
        #expect(Rules.countsTowardCap(vault, today: today) == (back ? 1 : 0))
        #expect(Rules.waitingList(vault, today: today).count == (back ? 0 : 1))
        #expect(Rules.chaseItems(vault, today: today).isEmpty)
        let counts = Rules.sidebarCounts(vault, today: today)
        #expect(counts.next == (back ? 1 : 0))
        #expect(counts.waiting == (back ? 0 : 1))
    }

    /// #86 — a blank who is no who: such an item is a deferral.
    @Test func aBlankWhoIsNoWho() {
        let action = TestVault.action(
            "Später", .waiting, waiting: WaitingInfo(who: "  ", followUp: TestVault.day(-1)))
        #expect(action.isWhoLessWaiting)
        #expect(Rules.isBackInNext(action, today: today))
        #expect(!TestVault.action("Nächste", .next).isWhoLessWaiting)
    }

    // W2 — a follow-up due today is already a chase item.
    @Test(arguments: [(-1, true), (0, true), (1, false)])
    func chaseBoundary(offset: Int, isChase: Bool) {
        let action = TestVault.action(
            "Warten", .waiting, waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(offset)))
        let vault = TestVault.snapshot(actions: [action])
        #expect(Rules.chaseItems(vault, today: today).isEmpty == !isChase)
        #expect(Rules.waitingList(vault, today: today).count == 1)
    }

    /// A5 — the archive boundary is "older than 30 days", so day 30 stays.
    @Test(arguments: [(30, false), (31, true)])
    func archiveBoundary(age: Int, archived: Bool) {
        let vault = TestVault.snapshot(actions: [TestVault.action("Erledigt", .done, completed: -age)])
        #expect(Rules.archiveCandidates(vault, today: today, calendar: calendar).isEmpty == !archived)
    }
}
