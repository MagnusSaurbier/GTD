import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureReview

/// Navigation, the two gates, and resume-after-interruption (§10).
@MainActor
struct ReviewSessionTests {

    // MARK: - Pages and the rail

    @Test func pageOrderCoversTheFourStagesThenTheSummary() {
        #expect(ReviewPage.allCases.first == .sweepInbox)
        #expect(ReviewPage.allCases.last == .summary)
        #expect(ReviewStage.sweep.pages == [.sweepInbox, .sweepDeferred, .sweepWaiting, .sweepStalled])
        #expect(ReviewStage.deck.pages == [.deckNext, .deckSomeday, .deckProjects])
        #expect(ReviewPage.summary.stage == nil)
        #expect(ReviewPage.summary.previous == nil)      // the note is already written
    }

    @Test func railMarksEarlierStagesDoneAndTheCurrentOneCurrent() {
        let rail = ReviewRailItem.rail(for: .deckSomeday)
        #expect(rail.count == 4)
        #expect(rail[0].isComplete)                       // sweep
        #expect(rail[1].isCurrent)                        // deck
        #expect(!rail[1].isComplete)
        #expect(!rail[3].isComplete)
        #expect(rail[0].subSteps.count == 4)
        // On the summary the whole review is behind us.
        #expect(ReviewRailItem.rail(for: .summary).allSatisfy { $0.isComplete })
    }

    @Test func startsOnTheCurrentIsoWeek() {
        let session = ReviewTest.session()
        let iso = Fixtures.today.isoWeek
        #expect(session.state.year == iso.year)
        #expect(session.state.week == iso.week)
        #expect(session.page == .sweepInbox)
    }

    // MARK: - The inbox gate (§10.1.1)

    @Test func theSweepCannotBeLeftWhileTheInboxHasItems() {
        let session = ReviewTest.session()                // fixtures: 5 items queued
        #expect(session.inboxRemaining > 0)
        #expect(!session.canContinue)
        #expect(session.blockReason != nil)
        session.advance()
        #expect(session.page == .sweepInbox)
    }

    @Test func anEmptyInboxOpensTheGate() {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        #expect(session.isInboxZero)
        #expect(session.blockReason == nil)
        session.advance()
        #expect(session.page == .sweepDeferred)
    }

    @Test func processedCountIsMeasuredAgainstTheQueueAtTheStart() async throws {
        let model = ReviewTest.model()
        let session = ReviewTest.session(model: model)
        let start = session.state.inboxAtStart
        #expect(start > 0)

        let item = try #require(Rules.inboxQueue(model.snapshot).first)
        try await model.send(.fileInbox(item.id, .trash))
        #expect(session.inboxProcessed == 1)
        #expect(session.inboxRemaining == start - 1)
    }

    // MARK: - The cap gate (§10.2)

    @Test func theDeckCannotBeLeftWhileNextIsOverTheCap() {
        let session = ReviewTest.session(ReviewTest.overCap(by: 3))
        walk(session, to: .deckProjects)
        #expect(session.isOverCap)
        #expect(session.blockReason != nil)
        session.advance()
        #expect(session.page == .deckProjects)
    }

    @Test func theDeckGateOpensOnceNextIsBackUnderTheCap() async {
        let snapshot = ReviewTest.overCap(by: 2)
        let model = ReviewTest.model(snapshot)
        let session = ReviewTest.session(model: model)
        walk(session, to: .deckProjects)
        #expect(!session.canContinue)

        // Demote the two hand-added items through the deck itself.
        for card in ReviewDeck.cards(for: .next, in: model.snapshot, today: Fixtures.today)
        where card.title.hasPrefix("Over cap") {
            await session.apply(.demote, to: card)
        }
        #expect(session.nextCount <= session.cap)
        #expect(session.canContinue)
        session.advance()
        #expect(session.page == .systemsCheck)
    }

    @Test func aVaultAtExactlyTheCapIsNotBlocked() {
        let session = ReviewTest.session(ReviewTest.overCap(by: 1))   // 14 + 1 = 15 of 15
        walk(session, to: .deckProjects)
        #expect(session.nextCount == session.cap)
        #expect(!session.isOverCap)
        #expect(session.blockReason == nil)
    }

    // MARK: - Back, and the rail's backwards-only jump

    @Test func backWalksTheFlatPageOrder() {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        walk(session, to: .deckNext)
        session.back()
        #expect(session.page == .sweepStalled)
        session.go(to: .sweep)
        #expect(session.page == .sweepInbox)
        #expect(!session.canGoBack)
        session.back()
        #expect(session.page == .sweepInbox)
    }

    @Test func theRailNeverJumpsForwardPastAGate() {
        let session = ReviewTest.session()                // inbox gate closed
        session.go(to: .reflection)
        #expect(session.page == .sweepInbox)
    }

    // MARK: - Persistence and resume (§10 "resumable")

    @Test func everyMutationIsPersisted() {
        let store = InMemoryReviewStateStore()
        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        #expect(store.load()?.page == .sweepInbox)        // the fresh session is written at once

        session.advance()
        #expect(store.load()?.page == .sweepDeferred)

        session.systemsCheck.workload = "Piling up."
        #expect(store.load()?.systemsCheck.workload == "Piling up.")

        session.answers[.goalForNextWeek] = "Finish the letter."
        #expect(store.load()?.review.goalForNextWeek == "Finish the letter.")
    }

    @Test func aSessionFromTheSameWeekResumesWhereItStopped() {
        var saved = ReviewTest.state(page: .systemsCheck)
        saved.systemsCheck.trust = "The triggers held."
        saved.changes.demoted = 3
        let store = InMemoryReviewStateStore(saved)

        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        #expect(session.page == .systemsCheck)
        #expect(session.systemsCheck.trust == "The triggers held.")
        #expect(session.state.changes.demoted == 3)
        #expect(session.staleState == nil)
    }

    @Test func aSessionFromAnEarlierWeekIsOfferedNotAdopted() {
        let iso = Fixtures.today.isoWeek
        let saved = ReviewTest.state(page: .deckNext, week: iso.week - 1)
        let store = InMemoryReviewStateStore(saved)

        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        #expect(session.page == .sweepInbox)              // this week starts fresh
        #expect(session.state.week == iso.week)
        #expect(session.staleState?.week == iso.week - 1)
    }

    @Test func continuingAStaleSessionKeepsItsWeekAndProgress() {
        let iso = Fixtures.today.isoWeek
        var saved = ReviewTest.state(page: .reflection, week: iso.week - 1)
        saved.review.achieved = "Drafted the letter."
        let store = InMemoryReviewStateStore(saved)

        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        session.continueStale()
        #expect(session.state.week == iso.week - 1)
        #expect(session.page == .reflection)
        #expect(session.answers[.achieved] == "Drafted the letter.")
        #expect(session.staleState == nil)
        #expect(store.load()?.week == iso.week - 1)
    }

    @Test func discardingAStaleSessionKeepsThisWeeksFreshOne() {
        let iso = Fixtures.today.isoWeek
        let store = InMemoryReviewStateStore(ReviewTest.state(page: .reflection, week: iso.week - 1))
        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        session.discardStale()
        #expect(session.staleState == nil)
        #expect(session.state.week == iso.week)
        #expect(session.page == .sweepInbox)
    }

    @Test func anAlreadySavedSessionIsNeverResumedIntoOrOffered() {
        var saved = ReviewTest.state(page: .summary)
        saved.isSaved = true
        let store = InMemoryReviewStateStore(saved)
        #expect(ReviewSession.resumable(in: store) == nil)

        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        #expect(session.page == .sweepInbox)             // a new review, not the finished one
        #expect(session.staleState == nil)
        #expect(!session.state.isSaved)
        // Starting a review *is* a review in progress, so the store now holds the fresh one.
        #expect(ReviewSession.resumable(in: store)?.page == .sweepInbox)
    }

    @Test func resumableReportsAnUnfinishedSession() {
        let store = InMemoryReviewStateStore(ReviewTest.state(page: .deckNext))
        #expect(ReviewSession.resumable(in: store)?.page == .deckNext)
        #expect(ReviewSession.resumable(in: InMemoryReviewStateStore()) == nil)
    }

    // MARK: - Helper

    private func walk(_ session: ReviewSession, to page: ReviewPage) {
        ReviewTest.walk(session, to: page)
    }
}
