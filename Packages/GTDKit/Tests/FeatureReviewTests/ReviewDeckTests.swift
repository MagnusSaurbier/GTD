import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureReview

/// Deck ordering, the choices each card offers, and what applying one actually writes (§10.2).
@MainActor
struct ReviewDeckTests {

    private var snapshot: VaultSnapshot { Fixtures.sampleSnapshot }

    // MARK: - Ordering

    @Test func theNextPhaseDealsTheNextListInItsOwnOrder() {
        let cards = ReviewDeck.cards(for: .next, in: snapshot, today: Fixtures.today)
        let expected = Rules.nextList(snapshot, today: Fixtures.today).map(\.id)
        #expect(cards.map(\.id) == expected)
        #expect(!cards.isEmpty)
        #expect(cards.allSatisfy { $0.choices == [.keep, .demote] })
    }

    @Test func backlogIsDealtBeforeMaybeAndEachOldestFirst() {
        let cards = ReviewDeck.cards(for: .backlogMaybe, in: snapshot, today: Fixtures.today)
        let statuses = cards.compactMap { $0.action?.status }
        #expect(!statuses.isEmpty)
        // No `maybe` may appear before a `backlog`.
        let firstMaybe = statuses.firstIndex(of: .maybe) ?? statuses.count
        #expect(!statuses.prefix(firstMaybe).contains(.maybe))
        #expect(statuses.dropFirst(firstMaybe).allSatisfy { $0 == .maybe })

        let backlogDates = cards.compactMap { $0.action }.filter { $0.status == .backlog }
            .map { $0.created ?? .distantFuture }
        #expect(backlogDates == backlogDates.sorted())
        #expect(cards.allSatisfy { $0.choices == [.promote, .keep, .trash] })
    }

    @Test func theProjectPhaseDealsOnHoldAndSomedayOnly() {
        let cards = ReviewDeck.cards(for: .projects, in: snapshot, today: Fixtures.today)
        #expect(cards.allSatisfy { $0.project?.status == .onHold || $0.project?.status == .someday })
        #expect(cards.contains { $0.project?.title == "Nebenjob" })
        #expect(!cards.contains { $0.project?.status == .active })
    }

    /// An on-hold project can still be dropped a step; one already on Someday cannot — the app
    /// never deletes, and "drop" must not quietly mean "done".
    @Test func somedayProjectsOfferNoDrop() {
        #expect(ReviewDeck.choices(for: .onHold) == [.activate, .keep, .drop])
        #expect(ReviewDeck.choices(for: .someday) == [.activate, .keep])
    }

    // MARK: - Commands

    @Test func keepWritesNothing() {
        let card = ReviewDeck.cards(for: .next, in: snapshot, today: Fixtures.today)[0]
        #expect(ReviewDeck.command(for: .keep, card: card) == nil)
    }

    @Test func demotePromoteAndTrashMapToStatusChanges() throws {
        let next = ReviewDeck.cards(for: .next, in: snapshot, today: Fixtures.today)[0]
        #expect(ReviewDeck.command(for: .demote, card: next) == .setStatus(next.id, .backlog, waiting: nil))

        let backlog = try #require(
            ReviewDeck.cards(for: .backlogMaybe, in: snapshot, today: Fixtures.today).first)
        #expect(ReviewDeck.command(for: .promote, card: backlog) == .setStatus(backlog.id, .next, waiting: nil))
        #expect(ReviewDeck.command(for: .trash, card: backlog) == .setStatus(backlog.id, .trash, waiting: nil))
    }

    @Test func activateAndDropRewriteTheProjectStatus() throws {
        let card = try #require(
            ReviewDeck.cards(for: .projects, in: snapshot, today: Fixtures.today).first)
        guard case let .updateProject(activated)? = ReviewDeck.command(for: .activate, card: card)
        else { Issue.record("expected updateProject"); return }
        #expect(activated.status == .active)
        #expect(activated.id == card.id)

        guard case let .updateProject(dropped)? = ReviewDeck.command(for: .drop, card: card)
        else { Issue.record("expected updateProject"); return }
        #expect(dropped.status == .someday)
    }

    @Test func aChoiceACardDoesNotOfferIsRefused() async {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let card = ReviewDeck.cards(for: .next, in: session.snapshot, today: Fixtures.today)[0]
        await session.apply(.trash, to: card)             // Next cards offer keep/demote only
        #expect(session.snapshot.action(card.id)?.status != .trash)
        #expect(session.state.handledDeckCards.isEmpty)
    }

    // MARK: - Applying through the session

    @Test func demotingMovesTheActionAndCountsTowardsTheSummary() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.demote, to: card)

        #expect(session.snapshot.action(card.id)?.status == .backlog)
        #expect(session.state.changes.demoted == 1)
        #expect(session.state.handledDeckCards == [card.id.path])
    }

    @Test func aDecidedCardIsNotDealtAgainInALaterPhase() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.demote, to: card)
        // It is `backlog` now, so the next phase would otherwise offer it a second time.
        #expect(!session.deckCards(for: .backlogMaybe).contains { $0.id == card.id })
        #expect(!session.deckCards(for: .next).contains { $0.id == card.id })
    }

    @Test func promotingIntoAFullNextIsRefusedAndTheCardStays() async throws {
        // Fixtures sit at 14/15; one promotion fits, the next one hits the cap.
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let cards = session.deckCards(for: .backlogMaybe)
        let first = try #require(cards.first)
        await session.apply(.promote, to: first)
        #expect(session.nextCount == session.cap)
        #expect(session.lastError == nil)

        let second = try #require(session.deckCards(for: .backlogMaybe).first)
        await session.apply(.promote, to: second)
        #expect(session.lastError == .nextCapReached(cap: session.cap))
        #expect(session.snapshot.action(second.id)?.status != .next)
        // Refused, so the card is still on the deck — never a silent skip.
        #expect(session.deckCards(for: .backlogMaybe).first?.id == second.id)
        #expect(session.state.changes.promoted == 1)
    }

    @Test func keepIsRecordedWithoutTouchingTheVault() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let before = session.snapshot
        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.keep, to: card)
        #expect(session.snapshot == before)
        #expect(session.state.changes.kept == 1)
        #expect(session.state.handledDeckCards == [card.id.path])
    }

    // MARK: - Keys (STYLEGUIDE §3.10)

    @Test func theKeyMapIsTheOneTheStyleGuideFixes() {
        #expect(DeckChoice.keep.key == "K")
        #expect(DeckChoice.demote.key == "D")
        #expect(DeckChoice.promote.key == "P")
        #expect(DeckChoice.trash.key == "T")
        // The project-shaped choices reuse the same two keys; a card never offers both.
        #expect(DeckChoice.activate.key == "P")
        #expect(DeckChoice.drop.key == "T")
    }

    @Test func keysResolveAgainstWhatTheCardOffers() {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let next = ReviewDeck.cards(for: .next, in: session.snapshot, today: Fixtures.today)[0]
        #expect(session.choice(forKey: "d", on: next) == .demote)
        #expect(session.choice(forKey: "K", on: next) == .keep)
        #expect(session.choice(forKey: "p", on: next) == nil)      // not offered here
    }

    @Test func theDeckCounterCountsDecidedCards() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        ReviewTest.walk(session, to: .deckNext)
        #expect(session.page == .deckNext)
        let total = session.deckCards(for: .next).count
        #expect(session.deckCounter == ReviewCopy.deckCounter(done: 0, total: total))
        let card = try #require(session.currentDeckCard)
        await session.apply(.keep, to: card)
        #expect(session.deckCounter == ReviewCopy.deckCounter(done: 1, total: total))
    }
}
