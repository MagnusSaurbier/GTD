import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// The acceptance suite of the two-step card (I1–I7, A3, W1, N6, R-3, R-4, R-9): LIFO order, no
/// skipping, the counter, mid-session captures, **every transition and every refusal of the state
/// machine**, validation flags, the cap choice, and undo returning the card to the step it was
/// filed from.
@MainActor
struct InboxSessionTests {

    /// R-4 — every card filed from the head of the sample queue is named after its capture text.
    private let filedTitle = "call the Hausverwaltung about the broken window handle"

    /// R-3 — everything Next demands, so a cap test is about the cap and not about a field.
    private func fillForNext(_ session: InboxSession, what: String) {
        session.draft.why = "It has been open for two weeks."
        session.draft.what = what
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
    }

    // MARK: - Queue (I1, I5)

    @Test func queueIsLIFOAndExcludesItemsDeferredToReview() {
        let (session, _, _) = InboxTestSupport.makeSession()
        let deferred = Fixtures.sampleSnapshot.inbox.filter { $0.reviewReason != nil }
        #expect(!deferred.isEmpty)

        #expect(session.queue.count == Fixtures.sampleSnapshot.inbox.count - deferred.count)
        // Newest first.
        #expect(session.queue.map(\.created) == session.queue.map(\.created).sorted(by: >))
        for item in deferred {
            #expect(!session.queue.contains { $0.id == item.id })
        }
        #expect(session.current?.id == session.queue.first?.id)
    }

    @Test func counterCountsDownAndTotalStaysPut() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let total = session.queue.count
        #expect(session.counter == "\(total) of \(total) left")

        session.draft.what = "Call the Hausverwaltung"
        await session.take(.someday)

        #expect(session.counter == "\(total - 1) of \(total) left")
        #expect(session.processed == 1)
    }

    @Test func thereIsNoSkip() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let first = try! #require(session.current)
        // Nothing in the public API advances the queue without filing the card.
        session.cancelSheet()
        session.collapse()
        session.refresh()
        #expect(session.current?.id == first.id)
    }

    /// I7 — a capture made while the session runs goes on top and is processed next.
    @Test func midSessionCaptureGoesOnTop() async {
        let (session, model, backend) = InboxTestSupport.makeSession()
        let before = session.queue.count
        let fresh = InboxTestSupport.capture("water the plants", at: "2026-09-19 120000")

        backend.capture(fresh)
        await InboxTestSupport.wait { model.snapshot.inboxItem(fresh.id) != nil }
        session.refresh()

        #expect(session.queue.count == before + 1)
        #expect(session.current?.id == fresh.id)
    }

    /// …but it never yanks away a card the user is already editing; it queues up right behind it.
    @Test func midSessionCaptureDoesNotStealAnEditedCard() async {
        let (session, model, backend) = await InboxTestSupport.openedActionCard()
        let editing = try! #require(session.current)
        session.draft.what = "Call about the window handle"

        let fresh = InboxTestSupport.capture("water the plants", at: "2026-09-19 120000")
        backend.capture(fresh)
        await InboxTestSupport.wait { model.snapshot.inboxItem(fresh.id) != nil }
        session.refresh()

        #expect(session.current?.id == editing.id)
        #expect(session.draft.what == "Call about the window handle")
        #expect(session.queue[1].id == fresh.id)
    }

    /// The same protection for a card that is merely **opened**: the step is work in progress
    /// even before a character is typed.
    @Test func midSessionCaptureDoesNotStealAnOpenedCard() async {
        let (session, model, backend) = await InboxTestSupport.openedActionCard()
        let opened = try! #require(session.current)
        #expect(session.draft.isPristine(for: opened))

        let fresh = InboxTestSupport.capture("water the plants", at: "2026-09-19 120000")
        backend.capture(fresh)
        await InboxTestSupport.wait { model.snapshot.inboxItem(fresh.id) != nil }
        session.refresh()

        #expect(session.current?.id == opened.id)
        #expect(session.step == .actionCard)
        #expect(session.queue[1].id == fresh.id)
    }

    // MARK: - The state machine (I2, STYLEGUIDE §3.5/§3.6)

    @Test func aSessionStartsOnTheSmallCard() {
        let (session, _, _) = InboxTestSupport.makeSession()
        #expect(session.step == .step1)
        #expect(session.exits == [.openAction, .openKeep, .trash, .deferToReview])
    }

    @Test func actionAndKnowledgeOpenTheirCards() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.openAction)
        #expect(session.step == .actionCard)
        #expect(session.exits == [.next, .someday, .waiting, .done, .collapse])

        session.collapse()
        await session.take(.openKeep)
        #expect(session.step == .keepCard)
        #expect(session.exits.first == .knowledge)
        #expect(session.exits.dropLast().last == .more)
        #expect(session.exits.last == .collapse)
    }

    /// STYLEGUIDE §3.6 — "Collapsing keeps everything already typed; the draft survives until the
    /// card is filed or the session ends."
    @Test func collapsingKeepsTheDraftAndReopeningShowsItAgain() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        fillForNext(session, what: "Ring the Hausverwaltung")
        session.draft.due = Fixtures.day(3)
        let typed = session.draft

        session.collapse()
        #expect(session.step == .step1)
        #expect(session.draft == typed)

        await session.take(.openKeep)
        session.draft.notes = "Frau Meier"
        session.collapse()
        await session.take(.openAction)
        #expect(session.step == .actionCard)
        #expect(session.draft.why == typed.why)
        #expect(session.draft.what == typed.what)
        #expect(session.draft.due == typed.due)
        #expect(session.draft.notes == "Frau Meier")
    }

    /// I4c/I5 — "Trash and Defer are reachable only from step 1."
    @Test func trashAndDeferAreRefusedFromAnOpenedCard() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)

        await session.take(.trash)
        #expect(session.refusal?.reason == .notAvailable(.trash, in: .actionCard))
        #expect(session.current?.id == item.id)
        #expect(model.snapshot.inboxItem(item.id) != nil)

        await session.take(.deferToReview)
        #expect(session.refusal?.reason == .notAvailable(.deferToReview, in: .actionCard))
        #expect(session.sheet == nil)

        // The Defer sheet's own confirm refuses just as flatly.
        await session.confirmDeferToReview(reason: "It is a decision, not an action.")
        #expect(session.refusal?.reason == .notAvailable(.deferToReview, in: .actionCard))
        #expect(model.snapshot.inboxItem(item.id)?.reviewReason == nil)

        // Collapsing makes both reachable again.
        session.collapse()
        await session.take(.trash)
        #expect(session.processed == 1)
    }

    @Test func aTierExitIsRefusedFromStepOne() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let before = model.snapshot.actions.count
        for exit in [InboxExit.next, .someday, .waiting, .done] {
            await session.take(exit)
            #expect(session.refusal?.reason == .notAvailable(exit, in: .step1))
        }
        #expect(model.snapshot.actions.count == before)
        #expect(session.processed == 0)
    }

    @Test func aKeepExitIsRefusedOutsideTheKeepCard() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)
        for exit in [InboxExit.knowledge, .list("Read"), .more] {
            await session.take(exit)
            #expect(session.refusal?.reason == .notAvailable(exit, in: .actionCard))
        }
        #expect(session.sheet == nil)
        #expect(model.snapshot.inboxItem(item.id) != nil)
    }

    @Test func collapseIsRefusedOnStepOne() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.collapse)
        #expect(session.refusal?.reason == .notAvailable(.collapse, in: .step1))
        #expect(session.step == .step1)
    }

    @Test func everyExitIsRefusedAtInboxZero() async {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.inbox = []
        let (session, _, _) = InboxTestSupport.makeSession(snapshot: snapshot)
        #expect(session.isFinished)
        await session.take(.openAction)
        #expect(session.refusal?.reason == .noCard)
        #expect(session.step == .step1)
    }

    /// `↓` on an opened card collapses it; on step 1 there is no drag at all.
    @Test func theDownwardDragCollapsesRatherThanFiles() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let size = CGSize(width: 360, height: 600)
        #expect(session.dragContext.step == .actionCard)

        let outcome = DragResolver.outcome(dx: 0, dy: 300, cardSize: size, in: session.dragContext)
        #expect(outcome == .collapse)
        await session.perform(try! #require(outcome))
        #expect(session.step == .step1)
        #expect(session.processed == 0)

        // Step 1 recognises nothing at all.
        #expect(DragResolver.outcome(dx: 0, dy: 300, cardSize: size, in: session.dragContext) == nil)
    }

    @Test func aFocusedFieldTurnsTheSwipesOff() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.isFieldFocused = true
        #expect(session.dragContext.isFieldFocused)
        let size = CGSize(width: 360, height: 600)
        #expect(DragResolver.outcome(dx: 300, dy: 0, cardSize: size, in: session.dragContext) == nil)
        session.isFieldFocused = false
        #expect(DragResolver.outcome(dx: 300, dy: 0, cardSize: size, in: session.dragContext)
                == .file(.next))
    }

    // MARK: - The Esc ladder (STYLEGUIDE §3.6 "Always")

    @Test func escapeIsALadderFromFieldToCardToQuit() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.isFieldFocused = true

        #expect(session.escape() == .blurField)
        #expect(!session.isFieldFocused)
        #expect(session.step == .actionCard, "the first Esc only blurs")

        #expect(session.escape() == .collapsed)
        #expect(session.step == .step1)

        #expect(session.escape() == .quit)
        #expect(session.step == .step1, "quitting is the view's business")
    }

    @Test func escapeCollapsesTheKeepCardToo() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.openKeep)
        #expect(session.escape() == .collapsed)
        #expect(session.step == .step1)
    }

    // MARK: - Draft (I2, §1)

    @Test func nothingIsPrefilled() {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(session.draft.text == item.text)
        #expect(session.draft.why.isEmpty)
        #expect(session.draft.what.isEmpty)
        #expect(session.draft.notes.isEmpty)
        #expect(session.draft.contexts.isEmpty)
        #expect(session.draft.timeBucket == nil)
        #expect(session.draft.deferDate == nil)
        #expect(session.draft.due == nil)
        #expect(session.draft.project == nil)
        #expect(session.draft.isPristine(for: item))
    }

    /// R-4 — the capture text *is* the title, and editing the title edits the capture. The
    /// note's file name follows from it (cut at a word boundary to ≤ 60 characters).
    @Test func theCaptureTextIsTheTitleAndStaysEditable() {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(session.draft.noteTitle == item.text)

        session.draft.what = "- [ ] Ring the Hausverwaltung\n- [ ] Note the case number"
        #expect(session.draft.noteTitle == item.text, "What? never renames the note any more")
        #expect(session.draft.suggestsProject)   // A2: two checkboxes

        session.draft.text = "Window handle: ask Frau Meier"
        #expect(session.draft.noteTitle == "Window handle ask Frau Meier")
    }

    @Test func filingWritesExactlyWhatTheDraftHolds() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls", "home"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Fixtures.day(3)

        await session.take(.someday)

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.status == .someday)
        #expect(action.why == "The window does not close.")
        #expect(action.contexts == ["calls", "home"])
        #expect(action.timeEstimate == 10)
        #expect(action.due == Fixtures.day(3))
        #expect(action.deferDate == nil)
        #expect(action.project == nil)
    }

    /// The raw text is editable in place; for Knowledge and Trash the capture file itself moves,
    /// so the edit has to reach the file first.
    @Test func editingTheRawTextIsPersistedBeforeFiling() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        session.draft.text = "call the Hausverwaltung about the window handle — Frau Meier"

        await session.take(.trash)

        #expect(model.snapshot.inboxItem(item.id) == nil)
        await session.undo()   // the filing is undone; the text edit stays on the file
        #expect(model.snapshot.inboxItem(item.id)?.text
                == "call the Hausverwaltung about the window handle — Frau Meier")
    }

    // MARK: - Validation flags (R-3, STYLEGUIDE §3.6)

    /// R-3/D12 — Next asks for all four, Someday only for `What?`, and every missing field is
    /// named so the card can mark it.
    @Test func nextAndSomedayAskForTheirRequiredFields() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)
        let actionsBefore = model.snapshot.actions.count

        await session.take(.next)
        #expect(session.refusal?.reason == .missing([.why, .what, .context, .timeEstimate]))
        #expect(session.missingFields == [.why, .what, .context, .timeEstimate])
        #expect(session.current?.id == item.id)
        #expect(session.step == .actionCard, "a refused card stays open")
        #expect(model.snapshot.actions.count == actionsBefore)

        let firstShake = session.shakeTrigger
        await session.take(.someday)
        #expect(session.refusal?.reason == .missing([.what]))
        #expect(session.shakeTrigger == firstShake + 1)   // shakes again
        #expect(session.missingFields == [.what], "the set is replaced, not accumulated")
        #expect(model.snapshot.actions.count == actionsBefore)

        // Filling them in lets the same card leave.
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        await session.take(.next)
        #expect(model.snapshot.actions.count == actionsBefore + 1)
    }

    /// "Every missing field shows a leading asterisk on its label **until it is filled**."
    @Test func anAsteriskDisappearsWhenItsFieldIsFilled() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        await session.take(.next)
        #expect(session.missingFields == [.why, .what, .context, .timeEstimate])
        #expect(session.isMissing(.why) && session.isMissing(.timeEstimate))

        session.draft.why = "It has been open for two weeks."
        #expect(!session.isMissing(.why))
        #expect(session.missingFields == [.what, .context, .timeEstimate])

        session.draft.what = "Ring them"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        #expect(session.missingFields.isEmpty)
        // Whitespace is not a value (§1 "no lying defaults").
        session.draft.why = "   "
        #expect(session.isMissing(.why))
    }

    /// The first missing **text** field takes the caret; a chip group alone asks for nothing.
    @Test func theFirstMissingTextFieldIsRequestedForFocus() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        await session.take(.next)
        #expect(session.focusRequest == .why)
        session.consumeFocusRequest()
        #expect(session.focusRequest == nil)

        session.draft.why = "Because."
        await session.take(.next)
        #expect(session.focusRequest == .what)

        session.draft.what = "Ring them"
        await session.take(.next)
        #expect(session.missingFields == [.context, .timeEstimate])
        #expect(session.focusRequest == nil, "there is no caret to put in a chip group")
    }

    /// I4/D13 — the 2-minute rule asks for nothing at all.
    @Test func doneFilesTheCardWithoutAskingForAnything() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        await session.take(.done)
        #expect(session.refusal == nil)
        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.status == .done)
        #expect(action.completedDate != nil)
    }

    /// Knowledge, the lists and Trash carry no commitment, so they never demand a *What?*.
    @Test func knowledgeListsAndTrashDoNotNeedAWhat() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let before = model.snapshot.actions.count
        await session.take(.openKeep)
        await session.take(.knowledge)
        #expect(session.refusal == nil)
        #expect(session.sheet == .knowledge)
        session.cancelSheet()

        await session.take(.list("Read"))
        #expect(session.refusal == nil)
        #expect(session.processed == 1)

        await session.take(.trash)
        #expect(session.refusal == nil)
        #expect(session.processed == 2)
        #expect(model.snapshot.actions.count == before)   // neither creates an action
    }

    @Test func contextsAndTimeMayStayEmptyForSomeday() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        session.draft.what = "Ring the Hausverwaltung"
        await session.take(.someday)

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.contexts.isEmpty)
        #expect(action.timeEstimate == nil)   // never 0 (§1)
    }

    // MARK: - Cap (A3, I4, ARCHITECTURE §6)

    @Test func capOffersAForcedChoiceAndKeepsTheDraft() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let cap = model.snapshot.config.nextCap
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap - 1)

        // One slot left: the first card fits.
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.take(.next)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)
        #expect(session.sheet == nil)
        #expect(session.step == .step1, "a filed card leaves the next one on step 1")

        // The next one is refused — the card stays open, with everything the user typed.
        await session.take(.openAction)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        session.draft.contexts = ["mac"]
        await session.take(.next)

        #expect(session.refusal?.reason == .capReached(cap: cap))
        #expect(session.sheet == .cap)
        #expect(session.capCandidates.count == cap)
        #expect(session.step == .actionCard)
        #expect(session.current?.id == refused.id)
        #expect(session.draft.what == "Write the rename script")
        #expect(session.draft.contexts == ["mac"])
        #expect(session.processed == 1)
        #expect(model.snapshot.inboxItem(refused.id) != nil)
    }

    /// Walkthrough 2026-09-21: the view calls `refresh()` whenever the inbox changes — also while
    /// a filing is still awaited. The fresh card `refresh()` attached to the next item was then
    /// overwritten with the filed card's state, so the next card showed (and would have filed)
    /// the previous capture's text.
    @Test func aRefreshDuringAFilingNeverLeaksTheFiledCardIntoTheNextOne() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let first = try! #require(session.current)
        fillForNext(session, what: "Ring the Hausverwaltung")

        let watcher = Task { @MainActor in
            var count = model.snapshot.inbox.count
            while !Task.isCancelled {
                if model.snapshot.inbox.count != count {
                    count = model.snapshot.inbox.count
                    session.refresh()
                }
                await Task.yield()
            }
        }
        await session.take(.next)
        watcher.cancel()

        let next = try! #require(session.current)
        #expect(next.id != first.id)
        #expect(session.step == .step1)
        #expect(session.draft.text == next.text)
        #expect(session.draft.why.isEmpty)
        #expect(session.draft.isPristine(for: next))
    }

    @Test func demotingOneNextItemFilesTheCardThatWasRefused() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let cap = model.snapshot.config.nextCap
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.take(.next)
        await session.take(.openAction)
        let second = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.take(.next)
        #expect(session.sheet == .cap)

        let victim = try! #require(session.capCandidates.first)
        await session.demoteAndRetry(victim.id)

        #expect(session.sheet == nil)
        #expect(model.snapshot.action(victim.id)?.status == .someday)
        let filed = try! #require(model.snapshot.actions.first {
            $0.title == CaptureText.title(of: second.text)
        })
        #expect(filed.status == .next)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)
        #expect(session.processed == 2)
        #expect(session.step == .step1)
    }

    /// The other half of the forced choice is **Cancel**, not a shortcut: there is no
    /// "send to Someday instead" any more (STYLEGUIDE §3.6, D14). Cancelling keeps the card, its
    /// step and its draft, and the user swipes ← themselves.
    @Test func theOtherHalfOfTheForcedChoiceIsCancelThenSomeday() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let cap = model.snapshot.config.nextCap
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.take(.next)
        await session.take(.openAction)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.take(.next)
        #expect(session.sheet == .cap)

        session.cancelSheet()
        #expect(session.capCandidates.isEmpty)
        await session.take(.someday)

        #expect(session.sheet == nil)
        let filed = try! #require(model.snapshot.actions.first {
            $0.title == CaptureText.title(of: refused.text)
        })
        #expect(filed.status == .someday)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap,
                "nothing was demoted behind the user's back")
        #expect(session.processed == 2)
    }

    @Test func cancellingTheCapSheetLeavesTheCardWhereItIs() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.take(.next)
        await session.take(.openAction)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.take(.next)

        session.cancelSheet()

        #expect(session.sheet == nil)
        #expect(session.step == .actionCard)
        #expect(session.current?.id == refused.id)
        #expect(session.draft.what == "Write the rename script")
        #expect(model.snapshot.inboxItem(refused.id) != nil)
    }

    /// The cap guards a card that carries a project chip exactly as it guards any other card —
    /// the card is an action either way (D33).
    @Test func capAppliesToACardWithAProjectChipToo() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.take(.next)   // now at the cap

        let project = try! #require(model.snapshot.projects.first { $0.status == .active })
        await session.take(.openAction)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Collect the forms")
        session.chooseProject(project.id)
        await session.take(.next)
        #expect(session.sheet == .cap)

        session.cancelSheet()
        await session.take(.someday)
        let filed = try! #require(model.snapshot.actions.first {
            $0.title == CaptureText.title(of: refused.text)
        })
        #expect(filed.status == .someday)
        #expect(filed.project == project.id)
    }

    // MARK: - Sub-flows (I4, I5, W1)

    @Test func knowledgeFilesTheCaptureAndRemembersTheFolder() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(session.suggestedKnowledgeFolder == nil)   // nothing is suggested on a fresh device

        await session.take(.openKeep)
        session.draft.notes = "Frau Meier"
        await session.confirmKnowledge(target: .folder("Studium/Thesis"))

        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.suggestedKnowledgeFolder == "Studium/Thesis")
        #expect(session.processed == 1)
        #expect(session.sheet == nil)
        #expect(session.step == .step1)
    }

    @Test func knowledgeSuggestsTheLastUsedFolderWithoutDecidingIt() {
        let (session, _, _) = InboxTestSupport.makeSession(lastKnowledgeFolder: "Technik")
        #expect(session.suggestedKnowledgeFolder == "Technik")
        // It is a suggestion, not a decision: the picker carries it as its own field.
        #expect(session.knowledgePicker.suggestion == "Technik")
        #expect(session.knowledgePicker.suggestedTarget == .folder("Technik"))
        #expect(!session.knowledgePicker.projects.isEmpty)
        #expect(session.knowledgePicker.projects.allSatisfy { $0.status == .active })
    }

    /// I4b/D36 — reference material for a project goes through the Knowledge branch.
    @Test func knowledgeCanFileIntoAnActiveProjectsFolder() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let project = try! #require(session.activeProjects.first)

        await session.take(.openKeep)
        await session.confirmKnowledge(target: .project(project.id))

        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.processed == 1)
        #expect(session.suggestedKnowledgeFolder == nil, "a project folder is not a Knowledge folder")
    }

    /// §5a — a list button files the card at once; nothing about it is a commitment (L1).
    @Test func aListFilesTheCardAtOnce() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.openKeep)
        session.draft.notes = "Marie empfiehlt es."
        await session.take(.list("Read"))
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(model.snapshot.listItems.contains { $0.list == "Read" && $0.title == filedTitle })
        #expect(session.undoToastLabel == "Added to Read")
    }

    /// STYLEGUIDE §3.6 — `Knowledge` first, the favourites in order, `More…` last, four slots on
    /// iPhone and eight on Mac. `More…` opens a sheet; a list button files.
    @Test func theNavbarIsKnowledgeFavouritesAndMore() async {
        let (phone, model, _) = InboxTestSupport.makeSession(platform: .iPhone)
        await phone.take(.openKeep)
        #expect(phone.navbarSlots.first?.kind == .knowledge)
        #expect(phone.navbarSlots.last?.kind == .more)
        #expect(phone.navbarSlots.count - 2 <= 4)
        let favourites = Rules.favouriteLists(model.snapshot).map(\.name)
        #expect(phone.exits.dropFirst().dropLast(2).map(\.title)
                == Array(favourites.prefix(4)))

        let (mac, _, _) = InboxTestSupport.makeSession(platform: .mac)
        await mac.take(.openKeep)
        #expect(mac.navbarSlots.count - 2 <= 8)
        // `More…` lists every list, not only the favourites.
        #expect(mac.allLists.count >= favourites.count)

        await mac.take(.more)
        #expect(mac.sheet == .more)
        #expect(mac.processed == 0, "More… opens a sheet, it does not file")
    }

    // MARK: - More… › New list… (I4b, L2)

    /// A vault whose `Lists/` folder is empty — what a fresh vault looks like.
    private var snapshotWithoutLists: VaultSnapshot {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.lists = []
        snapshot.listItems = []
        snapshot.config.favouriteLists = nil
        return snapshot
    }

    /// With no list the navbar is `Knowledge · More…` and the sheet must not be a dead end.
    @Test func aVaultWithoutListsSaysSoInsteadOfShowingAnEmptySheet() async {
        let (session, _, _) = InboxTestSupport.makeSession(snapshot: snapshotWithoutLists)
        await session.take(.openKeep)
        #expect(session.navbarSlots.map(\.kind) == [.knowledge, .more])
        #expect(session.hasNoLists)
        #expect(session.listsFolderName == "Lists")

        let (sample, _, _) = InboxTestSupport.makeSession()
        #expect(!sample.hasNoLists)
    }

    /// `New list…` creates the list and files the card into it, like picking an existing list.
    @Test func aNewListIsCreatedAndTheCardFiledIntoIt() async {
        let (session, model, _) = InboxTestSupport.makeSession(snapshot: snapshotWithoutLists)
        let item = try! #require(session.current)
        await session.take(.openKeep)
        session.draft.notes = "Marie empfiehlt es."
        await session.take(.more)

        let created = await session.createListAndFile(name: "  Read ")

        #expect(created)
        #expect(model.snapshot.lists.map(\.name) == ["Read"])
        #expect(model.snapshot.inboxItem(item.id) == nil)
        let filed = try! #require(model.snapshot.listItems.first { $0.list == "Read" })
        #expect(filed.title == filedTitle)
        #expect(filed.notes == "Marie empfiehlt es.")
        #expect(session.undoToastLabel == "Added to Read")
        #expect(session.sheet == nil)
        #expect(session.processed == 1)
        #expect(session.step == .step1)
        #expect(!session.hasNoLists)
        // No favourites chosen: the new list is a navbar slot for the next card (R-5).
        #expect(session.navbarSlots.map(\.kind) == [.knowledge, .list(name: "Read"), .more])
    }

    /// The reducer's name rules apply: a list that exists (in any case), nothing, and `Done`.
    @Test func aDuplicateOrInvalidListNameIsRefusedInTheSheet() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let before = model.snapshot.lists
        await session.take(.openKeep)
        await session.take(.more)

        #expect(await session.createListAndFile(name: "read") == false)
        #expect(session.newListRefusal == "A list named \"Read\" already exists.")
        #expect(session.sheet == .more, "the sheet stays open on a refusal")

        session.clearNewListRefusal()
        #expect(session.newListRefusal == nil)

        #expect(await session.createListAndFile(name: "   ") == false)
        #expect(session.newListRefusal == "A list name is required")
        #expect(await session.createListAndFile(name: "Done") == false)
        #expect(session.newListRefusal != nil)

        #expect(model.snapshot.lists == before)
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(session.processed == 0)

        session.cancelSheet()
        #expect(session.newListRefusal == nil)
    }

    /// Like every list exit, `New list…` belongs to the Knowledge / List card only.
    @Test func aNewListCannotBeCreatedFromAnotherStep() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        #expect(await session.createListAndFile(name: "Buy") == false)
        #expect(session.refusal?.reason == .notAvailable(.more, in: .step1))
        #expect(model.snapshot.list(named: "Buy") == nil)
    }

    /// R-9 — undo takes the card back out of the new list, onto the opened keep card with its
    /// notes. The list stays: `createList` has no inverse, and an empty folder costs nothing.
    @Test func undoAfterANewListReturnsTheCardAndKeepsTheList() async {
        let (session, model, _) = InboxTestSupport.makeSession(snapshot: snapshotWithoutLists)
        let item = try! #require(session.current)
        await session.take(.openKeep)
        session.draft.notes = "Second-hand is fine."
        await session.take(.more)
        await session.createListAndFile(name: "Wish")

        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .keepCard)
        #expect(session.draft.notes == "Second-hand is fine.")
        #expect(session.processed == 0)
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(model.snapshot.listItems.isEmpty)
        #expect(model.snapshot.lists.map(\.name) == ["Wish"])
    }

    /// W1/D39 — the follow-up date is required, who is optional, and `What?` is still asked for.
    @Test func waitingNeedsWhatAndAFollowUpDateButNotWho() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let followUp = WaitingInfo.suggestedFollowUp(from: Fixtures.today)

        await session.take(.waiting)
        #expect(session.sheet == .waiting)

        await session.confirmWaiting(WaitingInfo(who: "Marie", followUp: followUp))
        #expect(session.refusal?.reason == .missing([.what]))
        #expect(session.processed == 0)

        session.draft.what = "Monitor for Marie"
        await session.confirmWaiting(WaitingInfo(followUp: followUp))

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.status == .waiting)
        #expect(action.waitingFor == nil, "an empty who writes no line at all (D39)")
        #expect(action.followUpDate == followUp)
        #expect(followUp == Fixtures.today.adding(days: 7))   // W1's +7 d, confirmed by the user
    }

    /// R-8/I4a — the project chip. The card stays an action and names an existing project…
    @Test func theProjectChipLinksAnExistingProject() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let project = try! #require(model.snapshot.projects.first { $0.title == "DAAD" })

        session.chooseProject(project.id)
        #expect(session.projectChipTitle(in: model.snapshot) == "DAAD")
        session.draft.what = "Collect the forms"
        await session.take(.someday)

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.project == project.id)
        #expect(session.processed == 1)
    }

    /// …or one the picker creates with a name only, in the same command (D35).
    @Test func theProjectChipCanCreateTheProjectItLinks() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let projectsBefore = model.snapshot.projects.count

        // The create row is offered exactly while nothing matches the text exactly.
        #expect(session.projectPicker(search: "Fix the flat").createTitle == "Fix the flat")
        session.createProject(named: "Fix the flat")
        #expect(session.projectChipTitle(in: model.snapshot) == "Fix the flat")
        #expect(session.draft.project == nil, "never both (R-8)")
        session.draft.what = "Ring the Hausverwaltung"
        await session.take(.someday)

        #expect(model.snapshot.projects.count == projectsBefore + 1)
        let project = try! #require(model.snapshot.projects.first { $0.title == "Fix the flat" })
        #expect(project.area == nil)
        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.project == project.id)
        #expect(session.processed == 1)
    }

    @Test func choosingAProjectClearsAPendingNewOne() {
        let (session, model, _) = InboxTestSupport.makeSession()
        let project = try! #require(model.snapshot.projects.first { $0.title == "DAAD" })
        session.createProject(named: "Fix the flat")
        session.chooseProject(project.id)
        #expect(session.draft.newProjectTitle == nil)
        session.chooseProject(nil)
        #expect(session.projectChipTitle(in: model.snapshot) == nil)
        // An exact match never offers the create row (case-insensitive, trimmed).
        #expect(session.projectPicker(search: "  daad ").createTitle == nil)
    }

    @Test func deferToReviewNeedsAReasonAndLeavesTheQueue() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)

        await session.take(.deferToReview)
        #expect(session.sheet == .deferToReview)

        await session.confirmDeferToReview(reason: "  ")
        #expect(session.refusal?.reason == .reasonRequired)
        #expect(session.current?.id == item.id)

        await session.confirmDeferToReview(reason: "It is a decision, not an action.")

        #expect(model.snapshot.inboxItem(item.id)?.reviewReason == "It is a decision, not an action.")
        #expect(session.current?.id != item.id)
        session.refresh()
        #expect(!session.queue.contains { $0.id == item.id })   // I5: never back in the queue
        #expect(Rules.reviewDeferredInbox(model.snapshot).contains { $0.id == item.id })
    }

    // MARK: - Undo (R-9, I6, N6)

    @Test func undoBringsTheCardBackWithItsDraftRestored() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Fixtures.day(3)
        let filed = session.draft

        await session.take(.someday)
        #expect(session.current?.id != item.id)
        #expect(session.processed == 1)
        #expect(session.canUndo)

        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.draft == filed)
        #expect(session.processed == 0)
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(!model.snapshot.actions.contains { $0.title == filedTitle })
        #expect(session.summaryCounts.allSatisfy { $0.count == 0 })
    }

    /// R-9 — "undo returns the card to the head of the queue **in the step it was filed from**":
    /// the opened action card for Next / Someday / Waiting / Done.
    @Test func undoOfATierFilingReturnsTheOpenedActionCard() async {
        for exit in [InboxExit.next, .someday, .done] {
            let (session, _, _) = await InboxTestSupport.openedActionCard()
            let item = try! #require(session.current)
            fillForNext(session, what: "Ring the Hausverwaltung")
            let filed = session.draft

            await session.take(exit)
            #expect(session.step == .step1)
            await session.undo()

            #expect(session.current?.id == item.id)
            #expect(session.step == .actionCard, "\(exit) was filed from the opened action card")
            #expect(session.draft == filed)
        }
    }

    @Test func undoOfAWaitingFilingReturnsTheOpenedActionCard() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let item = try! #require(session.current)
        session.draft.what = "Monitor for Marie"
        let filed = session.draft

        await session.confirmWaiting(
            WaitingInfo(who: "Marie", followUp: WaitingInfo.suggestedFollowUp(from: Fixtures.today)))
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .actionCard)
        #expect(session.draft == filed)
    }

    /// R-9 — the opened Knowledge / List card for a list or a Knowledge filing.
    @Test func undoOfAKeepFilingReturnsTheOpenedKeepCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.openKeep)
        session.draft.notes = "Marie empfiehlt es."
        let filed = session.draft

        await session.take(.list("Read"))
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .keepCard)
        #expect(session.draft == filed)
        #expect(session.draft.notes == "Marie empfiehlt es.")
    }

    @Test func undoOfAKnowledgeFilingReturnsTheOpenedKeepCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.openKeep)
        session.draft.notes = "Frau Meier"

        await session.confirmKnowledge(target: .folder("Technik"))
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .keepCard)
        #expect(session.draft.notes == "Frau Meier")
    }

    /// R-9 — the small card for Trash and Defer to review, which are step-1 decisions.
    @Test func undoOfTrashReturnsTheSmallCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.trash)
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .step1)
    }

    @Test func undoOfDeferToReviewReturnsTheSmallCard() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.confirmDeferToReview(reason: "It is a decision, not an action.")
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.step == .step1)
        #expect(model.snapshot.inboxItem(item.id)?.reviewReason == nil)
    }

    @Test func theToastUsesTheCanonicalWording() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        #expect(session.undoToastLabel == nil)

        session.draft.what = "Ring the Hausverwaltung"
        await session.take(.someday)
        #expect(session.undoToastLabel == "Moved to Someday")   // STYLEGUIDE §6.3

        await session.take(.trash)
        #expect(session.undoToastLabel == "Moved to Trash")

        await session.confirmDeferToReview(reason: "It is a decision, not an action.")
        #expect(session.undoToastLabel == "Defer to review")
    }

    @Test func undoWithNothingFiledDoesNothing() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(!session.canUndo)
        await session.undo()
        #expect(session.current?.id == item.id)
        #expect(session.processed == 0)
        #expect(session.step == .step1)
    }

    // MARK: - Keys (STYLEGUIDE §3.6 Mac, R-10)

    @Test func stepOneKeysOpenTheCardsAndFileTheStepOneDecisions() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        #expect(await session.handle(character: "a"))
        #expect(session.step == .actionCard)
        #expect(session.escape() == .collapsed)

        #expect(await session.handle(character: "k"))
        #expect(session.step == .keepCard)
        #expect(session.escape() == .collapsed)

        #expect(await session.handle(character: "d"))
        #expect(session.sheet == .deferToReview)
        session.cancelSheet()

        let item = try! #require(session.current)
        #expect(await session.handle(character: "x"))
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.processed == 1)
    }

    @Test func actionCardKeysFileChipAndOpenTheProjectPicker() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        // Contexts on `1…8`, time buckets on `⇧1…⇧4`, when no field is focused.
        #expect(await session.handle(character: "1"))
        #expect(session.draft.contexts == [session.contexts[0]])
        #expect(await session.handle(character: "1"))
        #expect(session.draft.contexts.isEmpty, "the same key toggles it off again")
        #expect(await session.handle(character: "1", shift: true))
        #expect(session.draft.timeBucket == .upTo10)

        #expect(await session.handle(character: "p"))
        #expect(session.sheet == .project)
        session.cancelSheet()

        // `⌘↩` is Done; `→` is Next.
        session.draft.contexts = ["calls"]
        session.draft.why = "Because."
        session.draft.what = "Ring them"
        #expect(await session.handle(stroke: .arrowRight))
        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.status == .next)
    }

    @Test func aFocusedFieldSwallowsEveryKeyButEscape() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.isFieldFocused = true
        #expect(!(await session.handle(character: "1")))
        #expect(session.draft.contexts.isEmpty)
        #expect(!(await session.handle(stroke: .arrowRight)))
        #expect(session.processed == 0)
        // `Esc` is what blurs it.
        #expect(await session.handle(character: "\u{1B}"))
        #expect(!session.isFieldFocused)
    }

    @Test func aRebindTakesEffectInTheSessionAndInItsLegend() async throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.stepAction, to: .letter("N"))
        let (session, _, _) = InboxTestSupport.makeSession(bindings: bindings)

        #expect(!(await session.handle(character: "a")))
        #expect(session.step == .step1)
        #expect(await session.handle(character: "n"))
        #expect(session.step == .actionCard)

        session.collapse()
        #expect(session.legendString.hasPrefix("N Action · "))
    }

    @Test func aKeepCardDigitFilesIntoThatFavouriteList() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.openKeep)
        let first = try! #require(Rules.favouriteLists(model.snapshot).first)

        #expect(await session.handle(character: "2"))
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(model.snapshot.listItems.contains { $0.list == first.name && $0.title == filedTitle })

        // `0` is More…, and a slot with no favourite behind it does nothing.
        await session.take(.openKeep)
        #expect(await session.handle(character: "0"))
        #expect(session.sheet == .more)
        session.cancelSheet()
        #expect(!(await session.handle(character: "9")))
    }

    @Test func undoIsReachableFromEveryStep() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.trash)
        #expect(await session.handle(character: "z", command: true))
        #expect(session.current?.id == item.id)
        #expect(session.processed == 0)
    }

    // MARK: - Legend (STYLEGUIDE §3.6 Mac)

    @Test func theLegendReadsAsTheStyleGuideSpellsItPerStep() async {
        let (session, model, _) = InboxTestSupport.makeSession(platform: .mac)
        #expect(session.legendString == "A Action · K Knowledge / List · X Trash · D Defer to review")

        await session.take(.openAction)
        #expect(session.legendString
                == "← Someday  → Next    W Waiting · ⌘↩ Done · P Project · Esc Back")

        session.collapse()
        await session.take(.openKeep)
        let favourites = Rules.favouriteLists(model.snapshot).map(\.name)
        let expected = (["1 Knowledge"]
            + favourites.enumerated().map { "\($0.offset + 2) \($0.element)" }
            + ["0 More…", "Esc Back"]).joined(separator: " · ")
        #expect(session.legendString == expected)
    }

    // MARK: - Session summary (§5 reward moment)

    @Test func summaryCountsPerTargetAndFinishesAtInboxZero() async {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.inbox = Array(Fixtures.sampleSnapshot.inbox.prefix(2))   // both open
        let (session, _, _) = InboxTestSupport.makeSession(snapshot: snapshot)
        #expect(session.queue.count == 2)
        #expect(!session.isFinished)

        await session.take(.openAction)
        session.draft.what = "Ring the Hausverwaltung"
        await session.take(.someday)
        await session.take(.trash)

        #expect(session.isFinished)
        #expect(session.current == nil)
        #expect(session.processed == 2)
        let counts = Dictionary(uniqueKeysWithValues: session.summaryCounts.map { ($0.target, $0.count) })
        #expect(counts[.someday] == 1)
        #expect(counts[.trash] == 1)
        #expect(counts[.next] == 0)
        #expect(InboxCopy.targetBreakdown(session.summaryCounts) == "1 Someday · 1 Trash")
        #expect(session.elapsedMinutes == 0)
    }

    @Test func draftResetsForTheNextCardAndSoDoesTheStep() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.draft.why = "because"
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        await session.take(.someday)

        let next = try! #require(session.current)
        #expect(session.step == .step1, "every card starts on the small card again")
        #expect(session.draft.isPristine(for: next))
        #expect(session.draft.text == next.text)
        #expect(session.missingFields.isEmpty)
    }

    // MARK: - Swipe hint (STYLEGUIDE §3.6)

    /// "A one-time hint overlay shows ← Someday / → Next / ↓ Back **the first time an action card
    /// is opened**" — there is nothing to hint at on the small card.
    @Test func theHintAppearsWhenTheFirstActionCardOpens() async {
        let defaults = EphemeralInboxDefaults(didShowSwipeHint: false)
        let (session, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        #expect(!session.isSwipeHintVisible, "nothing swipes on step 1")

        await session.take(.openKeep)
        #expect(!session.isSwipeHintVisible, "the keep card has no commitment axis either")
        session.collapse()

        await session.take(.openAction)
        #expect(session.isSwipeHintVisible)
        #expect(defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
    }

    /// "Got it" has to change **observed** state, or the overlay stays up until the view is
    /// rebuilt — and the device-local flag has to keep it away next session.
    @Test func gotItHidesTheSwipeHintAtOnceAndForGood() async {
        let defaults = EphemeralInboxDefaults(didShowSwipeHint: false)
        let (session, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        await session.take(.openAction)
        #expect(session.isSwipeHintVisible)

        session.dismissSwipeHint()

        #expect(!session.isSwipeHintVisible)
        #expect(defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
        let (later, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        await later.take(.openAction)
        #expect(!later.isSwipeHintVisible)
    }

    @Test func theFirstCardFiledAlongTheCommitmentAxisDismissesTheHint() async {
        let defaults = EphemeralInboxDefaults(didShowSwipeHint: false)
        let (session, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        await session.take(.openAction)

        // A refused swipe taught nothing, and neither did a sheet target.
        await session.take(.next)
        await session.take(.waiting)
        session.cancelSheet()
        #expect(session.isSwipeHintVisible)

        session.draft.what = "Ring the Hausverwaltung"
        await session.take(.someday)

        #expect(session.processed == 1)
        #expect(!session.isSwipeHintVisible)
    }

    @Test func aDeviceThatSawTheHintNeverShowsItAgain() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.openAction)
        #expect(!session.isSwipeHintVisible)
    }
}

// MARK: - Make action (L4)

/// The small public entry point `FeatureLists` presents for "Make action": the opened action card
/// alone, over a list item, reusing exactly the inbox card's state and validation.
@MainActor
struct MakeActionModelTests {

    private func makeModel() -> (model: MakeActionModel, app: AppModel, item: ListItem) {
        let snapshot = Fixtures.sampleSnapshot
        let backend = TestBackend(snapshot: snapshot)
        let app = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        let item = snapshot.listItems.first { !$0.isFinished }!
        return (MakeActionModel(model: app, item: item), app, item)
    }

    @Test func itStartsFromTheListItemOnTheOpenedActionCard() {
        let (model, _, item) = makeModel()
        #expect(model.step == .actionCard)
        #expect(model.draft.text == item.title)
        #expect(model.draft.notes == item.notes)
        #expect(model.draft.why.isEmpty && model.draft.what.isEmpty)
        #expect(model.exits == [.next, .someday, .waiting, .done])
        #expect(!model.isFiled)
    }

    /// It is the same `RequiredField` rule, because it is the same `ActionCardState`.
    @Test func itAsksForTheSameRequiredFieldsAsTheInboxCard() async {
        let (model, app, item) = makeModel()
        let before = app.snapshot.actions.count

        await model.take(.next)
        #expect(model.refusal?.reason == .missing([.why, .what, .context, .timeEstimate]))
        #expect(model.missingFields == [.why, .what, .context, .timeEstimate])
        #expect(model.focusRequest == .why)
        #expect(app.snapshot.actions.count == before)
        #expect(app.snapshot.listItems.contains { $0.id == item.id }, "the item stayed in its list")

        model.draft.why = "Because."
        #expect(!model.isMissing(.why))
    }

    @Test func itPromotesTheItemIntoTheTierItLeavesBy() async {
        let (model, app, item) = makeModel()
        model.draft.why = "Because."
        model.draft.what = "Read the first chapter"
        model.draft.contexts = ["home"]
        model.draft.timeBucket = .upTo30

        await model.take(.next)

        #expect(model.isFiled)
        #expect(model.refusal == nil)
        #expect(!app.snapshot.listItems.contains { $0.id == item.id })
        let action = try! #require(app.snapshot.actions.first { $0.title == item.title })
        #expect(action.status == .next)
    }

    /// Someday needs only `What?`, and `Done` needs nothing — exactly the inbox card's table.
    @Test func somedayAndDoneAskForLessThanNext() async {
        let (someday, app, item) = makeModel()
        someday.draft.what = "Read it"
        await someday.take(.someday)
        #expect(someday.isFiled)
        #expect(app.snapshot.actions.first { $0.title == item.title }?.status == .someday)

        let (done, doneApp, doneItem) = makeModel()
        await done.take(.done)
        #expect(done.isFiled)
        #expect(doneApp.snapshot.actions.first { $0.title == doneItem.title }?.status == .done)
    }

    @Test func waitingGoesThroughTheSheetAndNeedsItsDate() async {
        let (model, app, item) = makeModel()
        await model.take(.waiting)
        #expect(model.sheet == .waiting)

        model.draft.what = "Hear back from Marie"
        await model.confirmWaiting(
            WaitingInfo(followUp: WaitingInfo.suggestedFollowUp(from: Fixtures.today)))
        #expect(model.isFiled)
        let action = try! #require(app.snapshot.actions.first { $0.title == item.title })
        #expect(action.status == .waiting)
        #expect(action.waitingFor == nil)
    }

    @Test func theCapIsTheSameForcedChoice() async {
        var snapshot = Fixtures.sampleSnapshot
        // Fill the last free slot so the promotion hits the cap.
        if let spare = snapshot.actions.firstIndex(where: { $0.status == .someday }) {
            snapshot.actions[spare].status = .next
            snapshot.actions[spare].deferDate = nil
        }
        let backend = TestBackend(snapshot: snapshot)
        let app = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        let item = try! #require(snapshot.listItems.first { !$0.isFinished })
        let model = MakeActionModel(model: app, item: item)
        model.draft.why = "Because."
        model.draft.what = "Read the first chapter"
        model.draft.contexts = ["home"]
        model.draft.timeBucket = .upTo30

        await model.take(.next)
        #expect(model.sheet == .cap)
        #expect(model.refusal?.reason == .capReached(cap: snapshot.config.nextCap))
        #expect(!model.isFiled)
        #expect(!model.capCandidates.isEmpty)

        let victim = try! #require(model.capCandidates.first)
        await model.demoteAndRetry(victim.id)

        #expect(model.isFiled)
        #expect(app.snapshot.action(victim.id)?.status == .someday)
        #expect(app.snapshot.actions.first { $0.title == item.title }?.status == .next)
    }

    /// Cancel leaves the item exactly where it was — nothing was written.
    @Test func cancelLeavesTheItemInItsList() async {
        let (model, app, item) = makeModel()
        model.draft.what = "Read it"
        await model.take(.next)          // refused: missing fields
        #expect(!model.missingFields.isEmpty)

        model.cancel()

        #expect(!model.isFiled)
        #expect(model.missingFields.isEmpty)
        #expect(app.snapshot.listItems.contains { $0.id == item.id })
        #expect(!app.snapshot.actions.contains { $0.title == item.title })
    }

    /// Anything outside the action card's four exits is refused, not silently done.
    @Test func stepOneAndKeepCardExitsAreRefused() async {
        let (model, app, item) = makeModel()
        for exit in [InboxExit.trash, .deferToReview, .openAction, .knowledge, .more, .collapse] {
            await model.take(exit)
            #expect(model.refusal?.reason == .notAvailable(exit, in: .actionCard))
        }
        #expect(!model.isFiled)
        #expect(app.snapshot.listItems.contains { $0.id == item.id })
    }

    @Test func itUsesTheActionCardsKeysAndLegend() async {
        let (model, app, item) = makeModel()
        #expect(await model.handle(character: "1"))
        #expect(model.draft.contexts == [model.contexts[0]])
        #expect(await model.handle(character: "p"))
        #expect(model.sheet == .project)
        model.cancelSheet()
        // Step-1 letters mean nothing here, and undo belongs to the list, not to the card.
        #expect(!(await model.handle(character: "x")))
        #expect(!(await model.handle(character: "z", command: true)))
        #expect(model.legend.map(\.label)
                == [Copy.someday, Copy.next, Copy.waiting, Copy.done, Copy.project])

        model.draft.why = "Because."
        model.draft.what = "Read it"
        model.draft.timeBucket = .upTo30
        #expect(await model.handle(stroke: .arrowLeft))
        #expect(model.isFiled)
        #expect(app.snapshot.actions.first { $0.title == item.title }?.status == .someday)
    }

    /// The Esc ladder here is one rung shorter: blur, then cancel.
    @Test func escapeBlursThenCancels() async {
        let (model, _, _) = makeModel()
        model.isFieldFocused = true
        #expect(await model.handle(character: "\u{1B}"))
        #expect(!model.isFieldFocused)
        #expect(!model.isFiled)
        #expect(await model.handle(character: "\u{1B}"))
        #expect(!model.isFiled)
    }
}
