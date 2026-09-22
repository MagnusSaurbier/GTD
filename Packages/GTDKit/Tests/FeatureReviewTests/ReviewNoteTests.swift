import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureReview

/// What `saveWeeklyReview` actually writes (§10.4): the eight answers, the next-week goal, and
/// the system-fix notes gathered along the way.
@MainActor
struct ReviewNoteTests {

    private func answered(_ session: ReviewSession) {
        session.answers[.wantedToAchieve] = "Finish the motivation letter."
        session.answers[.achieved] = "Two thirds of it."
        session.answers[.behaviorToChange] = "Stop researching mid-draft."
        session.answers[.whatToStop] = "Reading flat portals."
        session.answers[.howIGrew] = "Asked for help earlier."
        session.answers[.howToGrowFurther] = "Ship rough drafts."
        session.answers[.whatToTry] = "A 90-minute block with no tabs."
        session.answers[.goalForNextWeek] = "Letter submitted."
    }

    @Test func theNoteCarriesAllEightAnswersAndTheWeek() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        answered(session)

        let review = session.buildReview()
        let iso = Fixtures.today.isoWeek
        #expect(review.year == iso.year)
        #expect(review.week == iso.week)
        #expect(review.wantedToAchieve == "Finish the motivation letter.")
        #expect(review.achieved == "Two thirds of it.")
        #expect(review.behaviorToChange == "Stop researching mid-draft.")
        #expect(review.whatToStop == "Reading flat portals.")
        #expect(review.howIGrew == "Asked for help earlier.")
        #expect(review.howToGrowFurther == "Ship rough drafts.")
        #expect(review.whatToTry == "A 90-minute block with no tabs.")
        #expect(review.goalForNextWeek == "Letter submitted.")
    }

    @Test func systemFixNotesCombineDeferredItemsAndTheSystemsCheck() async throws {
        let session = ReviewTest.session()
        let item = try #require(session.currentDeferredItem)
        let reason = try #require(item.reviewReason)
        await session.fileDeferred(item, decision: .trash, systemFix: "Decisions get their own queue")

        session.systemsCheck.trust = "Nothing slipped."
        session.systemsCheck.routines = "Bedtime is drifting."
        // `workload` stays empty — an unanswered prompt must write nothing.

        let notes = session.buildReview().systemFixNotes
        #expect(notes.count == 3)
        #expect(notes[0] == ReviewCopy.systemFixNote(
            item: item.title, reason: reason, fix: "Decisions get their own queue"))
        #expect(notes[1].hasPrefix(ReviewCopy.promptTrust))
        #expect(notes[1].hasSuffix("Nothing slipped."))
        #expect(notes[2].hasPrefix(ReviewCopy.promptRoutines))
        #expect(!notes.contains { $0.contains(ReviewCopy.promptWorkload) })
    }

    @Test func aSystemFixNoteKeepsTheItemItsReasonAndTheFix() {
        let note = ReviewCopy.systemFixNote(
            item: "Decide whether to do a PhD",
            reason: "It is a decision, not an action.",
            fix: "Park decisions in a Decisions note.")
        #expect(note == "Decide whether to do a PhD (deferred: It is a decision, not an action.) "
            + "→ Park decisions in a Decisions note.")
        // Missing halves simply drop out — no empty brackets, no dangling arrow.
        #expect(ReviewCopy.systemFixNote(item: "X", reason: "", fix: "") == "X")
        #expect(ReviewCopy.systemFixNote(item: "X", reason: "", fix: "Y") == "X → Y")
    }

    @Test func savingWritesTheNoteAndMovesToTheSummary() async throws {
        let store = InMemoryReviewStateStore()
        let session = ReviewTest.session(ReviewTest.inboxZero, store: store)
        answered(session)
        ReviewTest.walk(session, to: .reflection)
        #expect(session.page == .reflection)
        #expect(session.isLastPageBeforeSave)

        let saved = await session.save()
        #expect(saved)
        #expect(session.page == .summary)
        #expect(session.state.isSaved)

        let note = try #require(session.snapshot.lastReview)
        let iso = Fixtures.today.isoWeek
        #expect(note.week == iso.week)
        #expect(note.goalForNextWeek == "Letter submitted.")
        #expect(note.savedAt != nil)                      // stamped by the reducer
        #expect(session.noteID.path == "GTD/Reviews/\(iso.year)/KW \(iso.week).md")

        // A finished review is not something to resume into.
        #expect(store.load() == nil)
        #expect(ReviewSession.resumable(in: store) == nil)
    }

    @Test func theSummaryReportsWhatTheReviewChanged() async throws {
        let model = ReviewTest.model(ReviewTest.inboxZero)
        let session = ReviewTest.session(model: model)

        let deferred = try #require(session.currentDeferredItem)
        await session.fileDeferred(deferred, decision: .trash, systemFix: "")

        let waiting = try #require(session.waitingItems.first)
        await session.apply(.resolve, to: waiting)

        let stalled = try #require(session.stalledProjects.first)
        await session.apply(.putOnHold, to: stalled)

        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.demote, to: card)

        let rows = Dictionary(uniqueKeysWithValues: session.summaryRows.map { ($0.id, $0.value) })
        #expect(rows["deferred"] == 1)
        #expect(rows["waiting"] == 1)
        #expect(rows["projects"] == 1)
        #expect(rows["demoted"] == 1)
        #expect(rows["promoted"] == 0)
        #expect(rows["trashed"] == 0)
        #expect(session.summaryRows.map(\.id).count == 7)
    }

    @Test func lastWeeksGoalIsShownBesideTheFirstQuestion() {
        let session = ReviewTest.session()
        #expect(session.lastWeeksGoal == Fixtures.lastReview.goalForNextWeek)
        #expect(session.lastReview?.week == 37)
        #expect(ReviewQuestion.wantedToAchieve.showsLastWeeksGoal)
        #expect(!ReviewQuestion.achieved.showsLastWeeksGoal)
    }

    @Test func noEarlierReviewMeansNoGoalRatherThanAnEmptyOne() {
        var snapshot = ReviewTest.inboxZero
        snapshot.lastReview = nil
        let session = ReviewTest.session(snapshot)
        #expect(session.lastWeeksGoal == nil)
    }

    /// N2 — re-saving the same week must not drop unknown frontmatter or body sections the
    /// existing note carries.
    @Test func reSavingTheSameWeekKeepsTheExistingNotesPassthrough() {
        var snapshot = ReviewTest.inboxZero
        let iso = Fixtures.today.isoWeek
        var existing = Fixtures.lastReview
        existing.year = iso.year
        existing.week = iso.week
        snapshot.lastReview = existing

        let session = ReviewTest.session(snapshot)
        #expect(session.buildReview().passthrough == existing.passthrough)

        // A different week starts from a clean note.
        var otherWeek = ReviewTest.inboxZero
        otherWeek.lastReview = Fixtures.lastReview       // KW 37, not this week
        #expect(ReviewTest.session(otherWeek).buildReview().passthrough == .empty)
    }

    @Test func theAnswersRoundTripThroughTheirSubscript() {
        var answers = WeeklyReviewAnswers()
        #expect(answers.isEmpty)
        for question in ReviewQuestion.allCases {
            answers[question] = question.rawValue
        }
        #expect(!answers.isEmpty)
        for question in ReviewQuestion.allCases {
            #expect(answers[question] == question.rawValue)
        }
        #expect(answers.goalForNextWeek == ReviewQuestion.goalForNextWeek.rawValue)
        #expect(ReviewQuestion.allCases.count == 8)
    }
}
