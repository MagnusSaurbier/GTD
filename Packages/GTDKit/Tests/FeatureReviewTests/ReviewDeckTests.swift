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

    /// A3 merged the two old "not now" tiers, so the phase deals one tier — every Someday action
    /// (§10.2, STYLEGUIDE §3.10: stalest first, project-linked before unlinked).
    @Test func theSomedayPhaseDealsTheWholeTier() {
        let cards = ReviewDeck.cards(for: .someday, in: snapshot, today: Fixtures.today)
        let statuses = cards.compactMap { $0.action?.status }
        #expect(!statuses.isEmpty)
        #expect(statuses.allSatisfy { $0 == .someday })
        #expect(cards.count == snapshot.actions.count { $0.status == .someday })
        #expect(cards.allSatisfy { $0.choices == [.promote, .keep, .trash] })
    }

    /// STYLEGUIDE §3.10/§2.2 — stalest first (days since `Action.modified`, the field
    /// "untouched" already reads for the staleness badge). A calendar-day count, so it is not
    /// merely `created` order — two fixture actions modified 7 and 20 days ago sort by that gap,
    /// not by which was captured first.
    @Test func theSomedayPhaseIsOrderedStalestFirst() {
        let cards = ReviewDeck.cards(for: .someday, in: snapshot, today: Fixtures.today)
        let days = cards.compactMap { $0.action }.map {
            Fixtures.today.days(since: Day($0.modified ?? .distantFuture, calendar: Fixtures.calendar))
        }
        #expect(days == days.sorted(by: >))
    }

    /// The explicit tie-breaker (§10.2 "project-linked before unlinked") for two cards that tie
    /// on staleness — and, below that, a total order by path so nothing depends on `sorted`'s
    /// stability.
    @Test func tiedStalenessPutsProjectLinkedFirstThenOrdersByPath() {
        let modified = Fixtures.date(Fixtures.day(-10), 9, 0)
        let linked = Action(
            id: NoteID(path: "Actions/Linked.md"), title: "Linked", status: .someday,
            project: NoteID(path: "Projects/no_area/Nebenjob/Nebenjob.md"),
            modified: modified, what: "Do it")
        let unlinkedA = Action(
            id: NoteID(path: "Actions/Unlinked A.md"), title: "Unlinked A", status: .someday,
            modified: modified, what: "Do it")
        let unlinkedB = Action(
            id: NoteID(path: "Actions/Unlinked B.md"), title: "Unlinked B", status: .someday,
            modified: modified, what: "Do it")

        var withTies = snapshot
        withTies.actions.removeAll { $0.status == .someday }
        withTies.actions.append(contentsOf: [unlinkedB, linked, unlinkedA])   // scrambled input

        let ids = ReviewDeck.cards(for: .someday, in: withTies, today: Fixtures.today).map(\.id)
        #expect(ids == [linked.id, unlinkedA.id, unlinkedB.id])
    }

    /// A note with no `modified` at all sorts as the most stale of all — never assumed recent
    /// (§1 "no lying defaults").
    @Test func aNeverTouchedActionSortsFirst() {
        let untouched = Action(
            id: NoteID(path: "Actions/Never touched.md"), title: "Never touched", status: .someday,
            what: "Do it")
        var withUntouched = snapshot
        withUntouched.actions.append(untouched)
        let ids = ReviewDeck.cards(for: .someday, in: withUntouched, today: Fixtures.today).map(\.id)
        #expect(ids.first == untouched.id)
    }

    /// STYLEGUIDE §3.10 — the Someday header's stat: every Someday action untouched > 30 days
    /// (§2.2's own threshold, `StalenessPolicy.actionAttentionDays`), counted over the whole
    /// tier rather than what is left to decide.
    @Test func untouchedOver30DaysCountsTheWholeSomedayTier() async throws {
        let stale = Action(
            id: NoteID(path: "Actions/Very stale.md"), title: "Very stale", status: .someday,
            modified: Fixtures.date(Fixtures.day(-40), 9, 0), what: "Do it")
        var withStale = snapshot
        withStale.actions.append(stale)
        let before = ReviewDeck.untouchedOver30DaysCount(in: snapshot, today: Fixtures.today)
        let after = ReviewDeck.untouchedOver30DaysCount(in: withStale, today: Fixtures.today)
        #expect(after == before + 1)

        // Deciding the card (it leaves what's left to review) does not change the stat — it is
        // about the pile, not progress through it.
        let session = ReviewTest.session(withStale)
        #expect(session.somedayUntouchedOver30DaysCount == after)
        let card = try #require(session.deckCards(for: .someday).first { $0.id == stale.id })
        await session.apply(.keep, to: card)
        #expect(session.somedayUntouchedOver30DaysCount == after)
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
        #expect(ReviewDeck.command(for: .demote, card: next) == .setStatus(next.id, .someday, waiting: nil))

        let someday = try #require(
            ReviewDeck.cards(for: .someday, in: snapshot, today: Fixtures.today).first)
        #expect(ReviewDeck.command(for: .promote, card: someday) == .setStatus(someday.id, .next, waiting: nil))
        // I4c — trash is a move, not a status.
        #expect(ReviewDeck.command(for: .trash, card: someday) == .trashAction(someday.id))
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
        #expect(session.snapshot.action(card.id) != nil)  // still there — nothing was trashed
        #expect(session.state.handledDeckCards.isEmpty)
    }

    // MARK: - Applying through the session

    @Test func demotingMovesTheActionAndCountsTowardsTheSummary() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.demote, to: card)

        #expect(session.snapshot.action(card.id)?.status == .someday)
        #expect(session.state.changes.demoted == 1)
        #expect(session.state.handledDeckCards == [card.id.path])
    }

    @Test func aDecidedCardIsNotDealtAgainInALaterPhase() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        let card = try #require(session.deckCards(for: .next).first)
        await session.apply(.demote, to: card)
        // It is `someday` now, so the next phase would otherwise offer it a second time.
        #expect(!session.deckCards(for: .someday).contains { $0.id == card.id })
        #expect(!session.deckCards(for: .next).contains { $0.id == card.id })
    }

    /// A3/D14 — promote handles the cap as a forced choice: `capChoice`/`capCard` are set (never
    /// a generic `lastError`, never automatic), `capCandidates` lists the current Next items, and
    /// the refused card stays on the deck.
    @Test func promotingIntoAFullNextIsRefusedAndTheCardStays() async throws {
        // Fixtures sit at 14/15; one promotion fits, the next one hits the cap.
        // R-3 — only a card that already carries Why?, What?, a context and a time estimate can
        // be promoted at all; the deck reports the missing fields for the others (T12).
        let session = ReviewTest.session(ReviewTest.inboxZero)
        func isComplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return !action.why.isEmpty && !action.what.isEmpty
                && !action.contexts.isEmpty && action.timeEstimate != nil
        }
        let cards = session.deckCards(for: .someday).filter(isComplete)
        let first = try #require(cards.first)
        await session.apply(.promote, to: first)
        #expect(session.nextCount == session.cap)
        #expect(session.lastError == nil)

        let second = try #require(session.deckCards(for: .someday).filter(isComplete).first)
        await session.apply(.promote, to: second)
        #expect(session.lastError == nil)                  // not a generic alert (STYLEGUIDE §3.10)
        #expect(session.capChoice == .promote)
        #expect(session.capCard?.id == second.id)
        #expect(!session.capCandidates.isEmpty)
        #expect(session.snapshot.action(second.id)?.status != .next)
        // Refused, so the card is still on the deck — never a silent skip.
        #expect(session.deckCards(for: .someday).filter(isComplete).first?.id == second.id)
        #expect(session.state.changes.promoted == 1)
    }

    /// `Demote` on the cap sheet demotes the chosen Next item and retries the refused promote in
    /// one step — the forced choice of D14, never automatic.
    @Test func demotingFromTheCapSheetRetriesThePromote() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        func isComplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return !action.why.isEmpty && !action.what.isEmpty
                && !action.contexts.isEmpty && action.timeEstimate != nil
        }
        while session.nextCount < session.cap {
            let card = try #require(session.deckCards(for: .someday).filter(isComplete).first)
            await session.apply(.promote, to: card)
        }
        let refused = try #require(session.deckCards(for: .someday).filter(isComplete).first)
        await session.apply(.promote, to: refused)
        let capCard = try #require(session.capCard)
        #expect(capCard.id == refused.id)

        let toDemote = try #require(session.capCandidates.first)
        await session.demoteAndRetryDeckCard(toDemote.id)

        #expect(session.capChoice == nil)
        #expect(session.capCard == nil)
        #expect(session.snapshot.action(toDemote.id)?.status == .someday)
        #expect(session.snapshot.action(refused.id)?.status == .next)   // the retry went through
        #expect(session.state.handledDeckCards.contains(refused.id.path))
    }

    /// `Cancel` on the cap sheet — no "send to Someday instead" (D14). The card is left
    /// undecided, and the vault is untouched.
    @Test func cancellingTheCapSheetLeavesTheCardUndecided() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        func isComplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return !action.why.isEmpty && !action.what.isEmpty
                && !action.contexts.isEmpty && action.timeEstimate != nil
        }
        while session.nextCount < session.cap {
            let card = try #require(session.deckCards(for: .someday).filter(isComplete).first)
            await session.apply(.promote, to: card)
        }
        let refused = try #require(session.deckCards(for: .someday).filter(isComplete).first)
        await session.apply(.promote, to: refused)
        #expect(session.capChoice != nil)

        session.cancelCapChoice()

        #expect(session.capChoice == nil)
        #expect(session.capCard == nil)
        #expect(session.snapshot.action(refused.id)?.status == .someday) // untouched
        #expect(!session.state.handledDeckCards.contains(refused.id.path))
        #expect(session.deckCards(for: .someday).contains { $0.id == refused.id })
    }

    /// R-3 — promote refused for missing required fields: the fields are named (never an alert),
    /// the card is not marked handled until the user picks `Edit` or `Keep`, and `Keep` records
    /// the decision without writing anything.
    @Test func promotingAnIncompleteSomedayCardNamesTheMissingFieldsAndOffersEditOrKeep() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        func isIncomplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return action.why.isEmpty || action.contexts.isEmpty || action.timeEstimate == nil
        }
        let card = try #require(session.deckCards(for: .someday).filter(isIncomplete).first)
        let beforeSnapshot = session.snapshot

        await session.apply(.promote, to: card)

        #expect(session.lastError == nil)                  // never the generic alert
        let fields = try #require(session.missingFieldsIssue)
        #expect(!fields.isEmpty)
        #expect(session.snapshot == beforeSnapshot)         // nothing was written
        // Never a silent skip: the card is still there, undecided.
        #expect(session.deckCards(for: .someday).contains { $0.id == card.id })
        #expect(!session.state.handledDeckCards.contains(card.id.path))

        session.keepDespiteMissingFields(card)

        #expect(session.missingFieldsIssue == nil)
        #expect(session.state.handledDeckCards.contains(card.id.path))
        #expect(session.state.changes.kept == 1)
        #expect(session.snapshot == beforeSnapshot)         // `keep` writes nothing
    }

    /// `Edit` clears the inline notice (so the caller can open the action) without marking the
    /// card handled — it is dealt again if the user comes back without fixing it.
    @Test func dismissingMissingFieldsForEditingLeavesTheCardUndecided() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        func isIncomplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return action.why.isEmpty || action.contexts.isEmpty || action.timeEstimate == nil
        }
        let card = try #require(session.deckCards(for: .someday).filter(isIncomplete).first)
        await session.apply(.promote, to: card)
        #expect(session.missingFieldsIssue != nil)

        session.dismissMissingFieldsForEditing()

        #expect(session.missingFieldsIssue == nil)
        #expect(!session.state.handledDeckCards.contains(card.id.path))
        #expect(session.deckCards(for: .someday).contains { $0.id == card.id })
    }

    /// Leaving the deck page clears a pending cap/missing-fields notice — a stale prompt must
    /// not survive a `Back`/`Continue`/rail jump.
    @Test func leavingTheDeckPageClearsAPendingCapOrMissingFieldsNotice() async throws {
        let session = ReviewTest.session(ReviewTest.inboxZero)
        ReviewTest.walk(session, to: .deckSomeday)
        func isIncomplete(_ card: DeckCard) -> Bool {
            guard let action = card.action else { return false }
            return action.why.isEmpty || action.contexts.isEmpty || action.timeEstimate == nil
        }
        let card = try #require(session.deckCards(for: .someday).filter(isIncomplete).first)
        await session.apply(.promote, to: card)
        #expect(session.missingFieldsIssue != nil)

        session.back()

        #expect(session.missingFieldsIssue == nil)
        #expect(session.capChoice == nil)
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

    /// R-10 (N7): the deck's key resolution goes through `KeyBindings`, so a rebind follows —
    /// the old key stops working and the new one takes over.
    @Test func keyResolutionFollowsARebind() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.deckDemote, to: .letter("J"))

        let session = ReviewTest.session(ReviewTest.inboxZero)
        let next = ReviewDeck.cards(for: .next, in: session.snapshot, today: Fixtures.today)[0]
        #expect(session.choice(forKey: "j", on: next, bindings: bindings) == .demote)
        #expect(session.choice(forKey: "d", on: next, bindings: bindings) == nil)
        // The default table (unaffected) still resolves `d`.
        #expect(session.choice(forKey: "d", on: next) == .demote)
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

/// L6 — "Lists never appear in the weekly review": no deck phase deals a list item, and the
/// deck a vault with lists produces is the deck the same vault without them produces.
@MainActor
struct ListItemsNeverEnterTheDeckTests {

    @Test(arguments: [DeckPhase.next, .someday, .projects])
    func noPhaseDealsAListItem(phase: DeckPhase) {
        var withoutLists = Fixtures.sampleSnapshot
        withoutLists.lists = []
        withoutLists.listItems = []

        #expect(!Fixtures.sampleSnapshot.listItems.isEmpty, "the fixture has list items to hide")
        let withLists = ReviewDeck.cards(for: phase, in: Fixtures.sampleSnapshot, today: Fixtures.today)
        #expect(withLists.map(\.id)
            == ReviewDeck.cards(for: phase, in: withoutLists, today: Fixtures.today).map(\.id))
        // Every card is an action or a project — a deck card cannot even hold a list item.
        #expect(withLists.allSatisfy { $0.action != nil || $0.project != nil })
        #expect(withLists.allSatisfy { card in
            guard let action = card.action else { return true }
            return !action.id.isInside(VaultLayout.default.lists)
        })
    }
}
