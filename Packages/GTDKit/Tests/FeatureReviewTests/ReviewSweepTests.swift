import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
import FeatureInbox
@testable import FeatureReview

/// The four sub-steps of the sweep (§10.1): deferred items with their reason and system fix,
/// waiting chase/bump/resolve, and stalled projects.
@MainActor
struct ReviewSweepTests {

    // MARK: - Deferred inbox items (I5)

    @Test func deferredItemsAreListedWithTheirReasonOldestFirst() {
        let session = ReviewTest.session()
        let items = session.deferredItems
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.reviewReason?.isEmpty == false })
        #expect(items.map(\.id) == Rules.reviewDeferredInbox(session.snapshot).map(\.id))
        // They are never part of the processing queue (I1/I5).
        let queued = Set(Rules.inboxQueue(session.snapshot).map(\.id))
        #expect(items.allSatisfy { !queued.contains($0.id) })
    }

    @Test func draftPlusTargetBecomesTheSameDecisionTheInboxCardWouldMake() {
        var draft = InboxSession.Draft(text: "Decide on the thesis chair")
        draft.what = "Mail three chairs"
        draft.why = "The topic depends on it"
        draft.contexts = ["mac"]
        draft.timeBucket = .upTo30

        guard case let .action(action)? = DeferredSweep.decision(target: .backlog, draft: draft)
        else { Issue.record("expected an action decision"); return }
        #expect(action.status == .backlog)
        #expect(action.title == "Mail three chairs")
        #expect(action.contexts == ["mac"])
        #expect(action.timeEstimate == 30)
        #expect(action.what == "Mail three chairs")
        #expect(action.why == "The topic depends on it")
    }

    @Test func targetsNeedingAPickerProduceNoDecisionUntilItIsAnswered() {
        let draft = InboxSession.Draft(text: "Something", what: "Do it")
        #expect(DeferredSweep.decision(target: .waiting, draft: draft) == nil)
        #expect(DeferredSweep.decision(target: .knowledge, draft: draft) == nil)
        #expect(DeferredSweep.decision(target: .project, draft: draft) == nil)
        // Parking it in the review again would make the escape hatch a loop.
        #expect(DeferredSweep.decision(target: .deferToReview, draft: draft) == nil)
        #expect(!DeferredSweep.targets.contains(.deferToReview))

        let waiting = WaitingInfo(who: "Prof. Weber", followUp: Fixtures.day(7))
        guard case let .action(action)? = DeferredSweep.decision(
            target: .waiting, draft: draft, waiting: waiting)
        else { Issue.record("expected an action decision"); return }
        #expect(action.status == .waiting)
        #expect(action.waiting == waiting)

        #expect(DeferredSweep.decision(target: .knowledge, draft: draft, knowledgeFolder: "Studium")
            == .knowledge(folder: "Studium", title: "Do it"))
    }

    @Test func nextAndBacklogStillNeedAWhat() {
        let empty = InboxSession.Draft(text: "Raw capture")
        #expect(!DeferredSweep.isComplete(empty, for: .next))
        #expect(!DeferredSweep.isComplete(empty, for: .backlog))
        #expect(DeferredSweep.isComplete(empty, for: .maybe))
        #expect(DeferredSweep.isComplete(empty, for: .trash))

        let filled = InboxSession.Draft(text: "Raw capture", what: "Write it down")
        #expect(DeferredSweep.isComplete(filled, for: .next))
    }

    @Test func filingADeferredItemRecordsTheSystemFixAndRemovesItFromTheList() async throws {
        let session = ReviewTest.session()
        let item = try #require(session.currentDeferredItem)
        let reason = try #require(item.reviewReason)

        var draft = InboxSession.Draft(item: item)
        draft.what = "Block 60 minutes to decide"
        let decision = try #require(DeferredSweep.decision(target: .backlog, draft: draft))

        await session.fileDeferred(item, decision: decision, systemFix: "Give decisions their own queue")

        #expect(session.deferredItems.isEmpty)
        #expect(session.state.changes.deferredHandled == 1)
        #expect(session.state.systemFixNotes == [
            ReviewCopy.systemFixNote(
                item: item.text, reason: reason, fix: "Give decisions their own queue"),
        ])
        #expect(session.state.systemFixNotes[0].contains(reason))
        #expect(session.snapshot.inboxItem(item.id) == nil)
    }

    @Test func anEmptySystemFixWritesNoLine() async throws {
        let session = ReviewTest.session()
        let item = try #require(session.currentDeferredItem)
        await session.fileDeferred(item, decision: .trash, systemFix: "   ")
        #expect(session.state.systemFixNotes.isEmpty)
        #expect(session.state.changes.deferredHandled == 1)
    }

    @Test func aRefusedFilingLeavesTheItemOnTheList() async throws {
        let session = ReviewTest.session()
        let item = try #require(session.currentDeferredItem)
        // No `What?`, no title — the reducer refuses a title-less action.
        let decision = InboxDecision.action(ActionDraft(title: "   ", status: .backlog))
        await session.fileDeferred(item, decision: decision, systemFix: "a fix")
        #expect(session.lastError != nil)
        #expect(session.deferredItems.contains { $0.id == item.id })
        #expect(session.state.systemFixNotes.isEmpty)
    }

    // MARK: - Waiting (§10.1.3)

    @Test func waitingItemsAreTheStandardWaitingList() {
        let session = ReviewTest.session()
        #expect(session.waitingItems.map(\.id)
            == Rules.waitingList(session.snapshot, today: Fixtures.today).map(\.id))
        #expect(!session.waitingItems.isEmpty)
    }

    @Test func chaseSuggestsASoonerFollowUpThanBumpAndResolveSuggestsNone() {
        #expect(WaitingSweep.suggestedFollowUp(for: .chase, today: Fixtures.today) == Fixtures.day(3))
        #expect(WaitingSweep.suggestedFollowUp(for: .bump, today: Fixtures.today) == Fixtures.day(7))
        #expect(WaitingSweep.suggestedFollowUp(for: .resolve, today: Fixtures.today) == nil)
        #expect(WaitingSweep.Choice.chase.needsFollowUp)
        #expect(!WaitingSweep.Choice.resolve.needsFollowUp)
    }

    @Test func chaseAndBumpRewriteTheFollowUpDateAndKeepTheWho() async throws {
        let session = ReviewTest.session()
        let action = try #require(session.waitingItems.first)
        let who = try #require(action.waitingFor)
        let newDate = Fixtures.day(4)

        await session.apply(.bump, to: action, followUp: newDate)

        let updated = try #require(session.snapshot.action(action.id))
        #expect(updated.status == .waiting)
        #expect(updated.waitingFor == who)
        #expect(updated.followUpDate == newDate)
        #expect(session.state.changes.waitingHandled == 1)
        #expect(!session.waitingItems.contains { $0.id == action.id })
    }

    /// W1 keeps who + date together, so a chase without a confirmed date writes nothing —
    /// the suggestion is UI state until the user taps it.
    @Test func chaseWithoutAConfirmedDateWritesNothing() async throws {
        let session = ReviewTest.session()
        let action = try #require(session.waitingItems.first)
        let before = session.snapshot
        await session.apply(.chase, to: action, followUp: nil)
        #expect(session.snapshot == before)
        #expect(session.state.changes.waitingHandled == 0)
    }

    /// Resolve goes to Backlog, not Next: the end of a wait is not by itself a commitment, and
    /// Backlog can never fail on the cap. The deck step right afterwards promotes it if it earns
    /// a slot.
    @Test func resolveMovesTheItemToBacklog() async throws {
        let session = ReviewTest.session()
        let action = try #require(session.waitingItems.first)
        await session.apply(.resolve, to: action)

        let updated = try #require(session.snapshot.action(action.id))
        #expect(updated.status == .backlog)
        #expect(updated.waitingFor == nil)
        #expect(updated.followUpDate == nil)
        #expect(session.state.changes.waitingHandled == 1)
    }

    // MARK: - Stalled projects (§10.1.4, P4)

    @Test func stalledProjectsAreTheOnesRulesReports() {
        let session = ReviewTest.session()
        #expect(session.stalledProjects.map(\.id)
            == Rules.stalledProjects(session.snapshot, today: Fixtures.today).map(\.id))
        #expect(session.stalledProjects.contains { $0.title == "Wohnungssuche" })
    }

    @Test func puttingAStalledProjectOnHoldTakesItOffTheList() async throws {
        let session = ReviewTest.session()
        let project = try #require(session.stalledProjects.first)
        await session.apply(.putOnHold, to: project)

        #expect(session.snapshot.project(project.id)?.status == .onHold)
        #expect(session.stalledProjects.isEmpty)
        #expect(session.state.changes.projectsTouched == 1)
    }

    @Test func shelvingAStalledProjectMovesItToSomeday() async throws {
        let session = ReviewTest.session()
        let project = try #require(session.stalledProjects.first)
        await session.apply(.shelve, to: project)
        #expect(session.snapshot.project(project.id)?.status == .someday)
    }

    /// `addNextAction` is a sheet (`WhatsNextSheet`), not a command: it must not rewrite the
    /// project status behind the user's back.
    @Test func addNextActionIssuesNoCommand() async throws {
        let session = ReviewTest.session()
        let project = try #require(session.stalledProjects.first)
        #expect(StalledSweep.command(.addNextAction, project: project) == nil)

        let before = session.snapshot
        await session.apply(.addNextAction, to: project)
        #expect(session.snapshot == before)
        #expect(session.state.changes.projectsTouched == 0)
        #expect(session.stalledProjects.isEmpty)   // handled, just not by a status change
    }

    @Test func aProjectThatGainedAnActionIsMarkedHandledWithoutACommand() async throws {
        let session = ReviewTest.session()
        let project = try #require(session.stalledProjects.first)
        session.markStalledHandled(project)
        session.markStalledHandled(project)                 // idempotent
        #expect(session.state.handledStalled == [project.id.path])
        #expect(session.state.changes.projectsTouched == 0)
    }
}
