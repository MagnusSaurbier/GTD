import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// A **whole processing session**, card after card, the way `docs/MANUAL_TEST.md` §1 asks a person
/// to drive it — as opposed to `InboxSessionTests`, which pins one transition or one refusal at a
/// time.
///
/// This is the session-layer half of `GTDServicesTests/InboxFlowJourneyTests`: the same journeys,
/// but through `InboxSession` (step 1 → opened card → exit → undo → next card) over
/// `InMemoryBackend` semantics, because a feature target may not import `GTDVault`/`GTDServices`
/// (ARCHITECTURE §2). What lands on **disk** is the other suite's business; what the card *does*
/// is this one's.
@MainActor
@Suite("A whole inbox session, card by card")
struct InboxSessionJourneyTests {

    /// Inbox zero in one run: every exit of STYLEGUIDE §3.6's three tables is used once, the
    /// counter walks down, the summary adds up, and the queue stays LIFO throughout (I1/I6).
    @Test func oneSessionToInboxZeroUsesEveryExitAndCountsWhatItDid() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        // Five cards: the sample vault's sixth is deferred to review and is not in the queue (I5).
        let queued = session.queue.map(\.id)
        #expect(queued.count == 5)
        #expect(session.counter == "5 of 5 left")
        #expect(session.step == .step1, "a session opens on the small card, never expanded")

        // ── Card 1: Action → Someday (the tier that only needs `What?`) ──────────────────────
        await session.take(.openAction)
        #expect(session.step == .actionCard)
        session.draft.what = "Ring them and ask."
        await session.take(.someday)
        #expect(session.step == .step1, "the next card always arrives collapsed")
        #expect(session.counter == "4 of 5 left")
        #expect(session.undoToastLabel == "Moved to Someday")

        // ── Card 2: Knowledge / List → a favourite list, straight off the navbar ─────────────
        await session.take(.openKeep)
        #expect(session.step == .keepCard)
        session.draft.notes = "Marie empfiehlt es."
        await session.take(.list("Read"))
        #expect(session.step == .step1)
        #expect(session.undoToastLabel == "Added to Read")

        // ── Card 3: Trash, a step-1 decision that asks nothing (I4c) ─────────────────────────
        let trashed = try! #require(session.current)
        await session.take(.trash)
        #expect(model.snapshot.inboxItem(trashed.id) == nil)
        #expect(session.undoToastLabel == "Moved to Trash")

        // ── Card 4: Knowledge / List → the Knowledge tree ────────────────────────────────────
        await session.take(.openKeep)
        await session.confirmKnowledge(target: .folder("Technik"), notes: "Ein Skript reicht.")
        #expect(session.step == .step1)

        // ── Card 5: Action → Done, the 2-minute rule (I4/D13) ────────────────────────────────
        await session.take(.openAction)
        await session.take(.done)

        #expect(session.isFinished, "inbox zero")
        #expect(session.counter == "0 of 5 left")
        #expect(session.processed == 5)
        let counts = Dictionary(uniqueKeysWithValues:
            session.summaryCounts.map { ($0.target, $0.count) })
        #expect(counts[.someday] == 1)
        #expect(counts[.list] == 1)
        #expect(counts[.trash] == 1)
        #expect(counts[.knowledge] == 1)
        #expect(counts[.done] == 1)
        #expect(counts[.next] == 0)
        // I5 — the review-deferred capture was never dealt a card and is still waiting.
        #expect(model.snapshot.inbox.count == 1)
        #expect(model.snapshot.inbox.first?.reviewReason != nil)
    }

    /// The action branch as the person meets it (R-3 → D14 → R-9): `→ Next` on an empty card is
    /// refused with asterisks, the filled card meets the cap sheet, demoting one lets it through,
    /// and `⌘Z` hands the whole card back — in the step it was filed from, with the draft intact.
    @Test func theActionCardIsRefusedForFieldsThenForTheCapAndUndoHandsItBack() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)

        // ── 1. Nothing typed: the refusal names all four fields and marks each (R-3) ─────────
        let shakeBefore = session.shakeTrigger
        await session.take(.next)
        #expect(session.step == .actionCard, "a refused card does not go anywhere")
        #expect(session.missingFields == [.why, .what, .context, .timeEstimate])
        #expect(session.isMissing(.why) && session.isMissing(.timeEstimate))
        #expect(session.shakeTrigger > shakeBefore, "the refusal is felt, not just read")
        #expect(session.focusRequest == .why, "focus goes to the first thing that is missing")
        #expect(model.snapshot.inboxItem(item.id) != nil)

        // An asterisk follows the draft, not the refusal: filling a field clears its mark at once.
        session.draft.why = "The window does not close."
        #expect(!session.isMissing(.why))
        #expect(session.isMissing(.what), "…and the others stay marked")

        // ── 2. Filled in — now it is the cap that refuses (D14) ──────────────────────────────
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        #expect(session.missingFields.isEmpty)

        // Take the vault to the cap with a note that already carries what Next demands.
        let filler = try! #require(model.snapshot.actions.first {
            $0.status == .someday && !$0.why.isEmpty && !$0.what.isEmpty
                && !$0.contexts.isEmpty && $0.timeEstimate != nil
        })
        try! await model.send(.setStatus(filler.id, .next, waiting: nil))
        #expect(Rules.isAtCap(model.snapshot, today: Fixtures.today))

        await session.take(.next)
        #expect(session.sheet == .cap, "the forced choice is a sheet, never an automatic demotion")
        #expect(session.step == .actionCard)
        #expect(!session.capCandidates.isEmpty)
        #expect(model.snapshot.inboxItem(item.id) != nil, "still the card")

        // ── 3. Cancel is the other half of the choice — and it files nothing (D14) ───────────
        session.cancelSheet()
        #expect(session.sheet == nil)
        #expect(session.step == .actionCard)
        #expect(model.snapshot.inboxItem(item.id) != nil)

        // ── 4. Demote one, and the same card goes through ────────────────────────────────────
        await session.take(.next)
        let demoted = try! #require(session.capCandidates.first { $0.id != filler.id })
        let filedDraft = session.draft
        await session.demoteAndRetry(demoted.id)

        #expect(session.sheet == nil)
        #expect(session.step == .step1, "the next card arrives collapsed")
        #expect(session.current?.id != item.id)
        #expect(model.snapshot.action(demoted.id)?.status == .someday)
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.undoToastLabel == "Moved to Next")

        // ── 5. R-9 — undo returns the card *opened*, with everything typed still there ───────
        await session.undo()
        #expect(session.current?.id == item.id)
        #expect(session.step == .actionCard, "Next was filed from the opened action card")
        #expect(session.draft == filedDraft)
        #expect(session.processed == 0)
    }

    /// An exit belongs to a step, and taking it from the wrong one is a **refusal**, not a quiet
    /// no-op (T08's ruling, STYLEGUIDE §3.6 "Trash and Defer are reachable only from step 1").
    /// The card, the draft and the vault are all untouched by the attempt.
    @Test func anExitFromTheWrongStepIsRefusedAndChangesNothing() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let inboxBefore = model.snapshot.inbox

        // Step 1 has no tier exits: the card has not been called an action yet.
        for exit in [InboxExit.next, .someday, .waiting, .done, .knowledge, .list("Read")] {
            #expect(!session.canTake(exit), "\(exit) is not a step-1 exit")
            await session.take(exit)
            #expect(session.step == .step1)
            #expect(session.refusal?.reason == .notAvailable(exit, in: .step1))
        }

        // The opened action card has no Trash and no Defer to review.
        await session.take(.openAction)
        for exit in [InboxExit.trash, .deferToReview] {
            #expect(!session.canTake(exit))
            await session.take(exit)
            #expect(session.step == .actionCard, "the card stayed open")
            #expect(session.refusal?.reason == .notAvailable(exit, in: .actionCard))
        }

        // …and the Knowledge / List card has no tiers.
        session.collapse()
        await session.take(.openKeep)
        await session.take(.next)
        #expect(session.step == .keepCard)
        #expect(session.refusal?.reason == .notAvailable(.next, in: .keepCard))

        #expect(session.current?.id == item.id, "five refusals later, it is still the same card")
        #expect(session.processed == 0)
        #expect(model.snapshot.inbox == inboxBefore, "and the vault never heard about any of it")
    }

    /// Collapsing is not cancelling (I2/D10): `↓` and `Esc` take the card back to step 1 with
    /// everything typed still in the draft, and re-opening it shows the same card again. The draft
    /// only dies with the card.
    @Test func collapsingAndReopeningKeepsEverythingTyped() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)
        session.draft.why = "It has been open for two weeks."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.due = Fixtures.day(3)
        let typed = session.draft

        await session.take(.collapse)
        #expect(session.step == .step1)
        #expect(session.current?.id == item.id, "collapsing never files and never skips")

        await session.take(.openAction)
        #expect(session.step == .actionCard)
        #expect(session.draft == typed)

        // The `Esc` ladder is the same rung from the keyboard.
        #expect(session.escape() == .collapsed)
        #expect(session.step == .step1)
        #expect(session.escape() == .quit, "…and one more rung quits the session")

        // Switching to the *other* opened card keeps the draft too — it is one draft per card.
        await session.take(.openKeep)
        #expect(session.step == .keepCard)
        #expect(session.draft.why == typed.why, "the action half is still there behind the notes")
    }
}
