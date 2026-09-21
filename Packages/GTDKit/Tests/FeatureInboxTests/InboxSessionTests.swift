import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureInbox

/// The acceptance suite of T20: LIFO order, no skipping, the counter, mid-session captures,
/// validation, every sub-flow, the cap choice and undo restoring the draft (I1–I7, A3, W1, N6).
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
        let (session, _, _) = InboxTestSupport.makeSession()
        let total = session.queue.count
        #expect(session.counter == "\(total) of \(total) left")

        session.draft.what = "Call the Hausverwaltung"
        await session.choose(.someday)

        #expect(session.counter == "\(total - 1) of \(total) left")
        #expect(session.processed == 1)
    }

    @Test func thereIsNoSkip() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        let first = try! #require(session.current)
        // Nothing in the public API advances the queue without filing the card.
        session.cancelSheet()
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
        let (session, model, backend) = InboxTestSupport.makeSession()
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

    // MARK: - Draft (I2, §1)

    @Test func nothingIsPrefilled() {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(session.draft.text == item.text)
        #expect(session.draft.why.isEmpty)
        #expect(session.draft.what.isEmpty)
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
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls", "home"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Fixtures.day(3)

        await session.choose(.someday)

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

        await session.choose(.trash)

        #expect(model.snapshot.inboxItem(item.id) == nil)
        await session.undo()   // the filing is undone; the text edit stays on the file
        #expect(model.snapshot.inboxItem(item.id)?.text
                == "call the Hausverwaltung about the window handle — Frau Meier")
    }

    // MARK: - Validation (STYLEGUIDE §3.6)

    /// R-3/D12 — Next asks for all four, Someday only for `What?`, and every missing field is
    /// named so the card can mark it (STYLEGUIDE §3.6).
    @Test func nextAndSomedayAskForTheirRequiredFields() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let actionsBefore = model.snapshot.actions.count

        await session.choose(.next)
        #expect(session.validation?.issue == .missing([.why, .what, .context, .timeEstimate]))
        #expect(session.missingFields == [.why, .what, .context, .timeEstimate])
        #expect(session.current?.id == item.id)
        #expect(model.snapshot.actions.count == actionsBefore)

        let firstNonce = try! #require(session.validation?.nonce)
        await session.choose(.someday)
        #expect(session.validation?.issue == .missing([.what]))
        #expect(session.validation?.nonce == firstNonce + 1)   // shakes again
        #expect(model.snapshot.actions.count == actionsBefore)

        // Filling them in lets the same card leave.
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        await session.choose(.next)
        #expect(model.snapshot.actions.count == actionsBefore + 1)
    }

    /// I4/D13 — the 2-minute rule asks for nothing at all.
    @Test func doneFilesTheCardWithoutAskingForAnything() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        await session.choose(.done)
        #expect(session.validation == nil)
        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.status == .done)
        #expect(action.completedDate != nil)
    }

    /// Knowledge and Trash carry no commitment, so they never demand a *What?*.
    /// (Replaces the old second-tier test: that tier merged into Someday, which *does* require
    /// a What? — `nextAndSomedayNeedAWhat` covers it.)
    @Test func knowledgeAndTrashDoNotNeedAWhat() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let before = model.snapshot.actions.count
        await session.choose(.knowledge)
        #expect(session.validation == nil)
        #expect(session.sheet == .knowledge)
        session.sheet = nil

        await session.choose(.trash)
        #expect(session.validation == nil)
        #expect(session.processed == 1)
        #expect(model.snapshot.actions.count == before)   // trash creates no action
    }

    @Test func contextsAndTimeMayStayEmptyForSomeday() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.someday)

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.contexts.isEmpty)
        #expect(action.timeEstimate == nil)   // never 0 (§1)
    }

    // MARK: - Cap (A3, I4, ARCHITECTURE §6)

    @Test func capOffersAForcedChoiceAndKeepsTheDraft() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let cap = model.snapshot.config.nextCap
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap - 1)

        // One slot left: the first card fits.
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.choose(.next)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)
        #expect(session.sheet == nil)

        // The next one is refused — the card stays, with everything the user typed.
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        session.draft.contexts = ["mac"]
        await session.choose(.next)

        #expect(session.sheet == .cap)
        #expect(session.capCandidates.count == cap)
        #expect(session.current?.id == refused.id)
        #expect(session.draft.what == "Write the rename script")
        #expect(session.draft.contexts == ["mac"])
        #expect(session.processed == 1)
        #expect(model.snapshot.inboxItem(refused.id) != nil)
    }

    @Test func demotingOneNextItemFilesTheCardThatWasRefused() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let cap = model.snapshot.config.nextCap
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.choose(.next)
        let second = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.choose(.next)
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
    }

    /// The other half of the forced choice is **Cancel**, not a shortcut: there is no
    /// "send to Someday instead" any more (STYLEGUIDE §3.6, D14). Cancelling keeps the card and
    /// its draft, and the user swipes ← themselves.
    @Test func theOtherHalfOfTheForcedChoiceIsCancelThenSomeday() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let cap = model.snapshot.config.nextCap
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.choose(.next)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.choose(.next)
        #expect(session.sheet == .cap)

        session.cancelSheet()
        await session.choose(.someday)

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
        let (session, model, _) = InboxTestSupport.makeSession()
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.choose(.next)
        let refused = try! #require(session.current)
        fillForNext(session, what: "Write the rename script")
        await session.choose(.next)

        session.cancelSheet()

        #expect(session.sheet == nil)
        #expect(session.current?.id == refused.id)
        #expect(session.draft.what == "Write the rename script")
        #expect(model.snapshot.inboxItem(refused.id) != nil)
    }

    /// The cap guards a card that carries a project chip exactly as it guards any other card —
    /// the card is an action either way (D33).
    @Test func capAppliesToACardWithAProjectChipToo() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        fillForNext(session, what: "Ring the Hausverwaltung")
        await session.choose(.next)   // now at the cap

        let project = try! #require(model.snapshot.projects.first { $0.status == .active })
        let refused = try! #require(session.current)
        fillForNext(session, what: "Collect the forms")
        session.chooseProject(project.id)
        await session.choose(.next)
        #expect(session.sheet == .cap)

        session.cancelSheet()
        await session.choose(.someday)
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

        await session.confirmKnowledge(target: .folder("Studium/Thesis"), notes: "Frau Meier")

        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.suggestedKnowledgeFolder == "Studium/Thesis")
        #expect(session.processed == 1)
        #expect(session.sheet == nil)
    }

    @Test func knowledgeSuggestsTheLastUsedFolder() {
        let (session, _, _) = InboxTestSupport.makeSession(lastKnowledgeFolder: "Technik")
        #expect(session.suggestedKnowledgeFolder == "Technik")
    }

    /// I4b/D36 — reference material for a project goes through the Knowledge branch.
    @Test func knowledgeCanFileIntoAnActiveProjectsFolder() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let project = try! #require(session.activeProjects.first)

        await session.confirmKnowledge(target: .project(project.id))

        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.processed == 1)
        #expect(session.suggestedKnowledgeFolder == nil, "a project folder is not a Knowledge folder")
    }

    /// §5a — a list button files the card at once; nothing about it is a commitment (L1).
    @Test func aListFilesTheCardAtOnce() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.confirmList(name: "Read", notes: "Marie empfiehlt es.")
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(model.snapshot.listItems.contains { $0.list == "Read" && $0.title == filedTitle })
    }

    /// W1/D39 — the follow-up date is required, who is optional, and `What?` is still asked for.
    @Test func waitingNeedsWhatAndAFollowUpDateButNotWho() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let followUp = WaitingInfo.suggestedFollowUp(from: Fixtures.today)

        await session.confirmWaiting(WaitingInfo(who: "Marie", followUp: followUp))
        #expect(session.validation?.issue == .missing([.what]))
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
        let (session, model, _) = InboxTestSupport.makeSession()
        let project = try! #require(model.snapshot.projects.first { $0.title == "DAAD" })

        session.chooseProject(project.id)
        #expect(session.projectChipTitle(in: model.snapshot) == "DAAD")
        session.draft.what = "Collect the forms"
        await session.choose(.someday)

        let action = try! #require(model.snapshot.actions.first { $0.title == filedTitle })
        #expect(action.project == project.id)
        #expect(session.processed == 1)
    }

    /// …or one the picker creates with a name only, in the same command (D35).
    @Test func theProjectChipCanCreateTheProjectItLinks() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let projectsBefore = model.snapshot.projects.count

        session.createProject(named: "Fix the flat")
        #expect(session.projectChipTitle(in: model.snapshot) == "Fix the flat")
        #expect(session.draft.project == nil, "never both (R-8)")
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.someday)

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
    }

    @Test func deferToReviewNeedsAReasonAndLeavesTheQueue() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)

        await session.confirmDeferToReview(reason: "  ")
        #expect(session.validation?.issue == .reasonRequired)
        #expect(session.current?.id == item.id)

        await session.confirmDeferToReview(reason: "It is a decision, not an action.")

        #expect(model.snapshot.inboxItem(item.id)?.reviewReason == "It is a decision, not an action.")
        #expect(session.current?.id != item.id)
        session.refresh()
        #expect(!session.queue.contains { $0.id == item.id })   // I5: never back in the queue
        #expect(Rules.reviewDeferredInbox(model.snapshot).contains { $0.id == item.id })
    }

    // MARK: - Undo (I6, N6)

    @Test func undoBringsTheCardBackWithItsDraftRestored() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Fixtures.day(3)
        let filed = session.draft

        await session.choose(.someday)
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

    @Test func undoAlsoRestoresASubFlowCard() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        session.draft.what = "Monitor for Marie"
        let filed = session.draft

        await session.confirmWaiting(
            WaitingInfo(who: "Marie", followUp: WaitingInfo.suggestedFollowUp(from: Fixtures.today)))
        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.draft == filed)
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(!model.snapshot.actions.contains { $0.waitingFor == "Marie" })
    }

    @Test func theToastUsesTheCanonicalWording() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        #expect(session.undoToastLabel == nil)

        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.someday)
        #expect(session.undoToastLabel == "Moved to Someday")   // STYLEGUIDE §6.3

        await session.choose(.trash)
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
    }

    // MARK: - Session summary (§5 reward moment)

    @Test func summaryCountsPerTargetAndFinishesAtInboxZero() async {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.inbox = Array(Fixtures.sampleSnapshot.inbox.prefix(2))   // both open
        let (session, _, _) = InboxTestSupport.makeSession(snapshot: snapshot)
        #expect(session.queue.count == 2)
        #expect(!session.isFinished)

        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.someday)
        await session.choose(.trash)

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

    @Test func draftResetsForTheNextCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.draft.why = "because"
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        await session.choose(.someday)

        let next = try! #require(session.current)
        #expect(session.draft.isPristine(for: next))
        #expect(session.draft.text == next.text)
    }

    // MARK: - Swipe hint (STYLEGUIDE §3.6)

    /// "Got it" has to change **observed** state, or the overlay stays up until the view is
    /// rebuilt — and it has to reach the device-local flag, or it comes back next session.
    @Test func gotItHidesTheSwipeHintAtOnceAndForGood() {
        let defaults = EphemeralInboxDefaults(didShowSwipeHint: false)
        let (session, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        #expect(session.isSwipeHintVisible)

        session.dismissSwipeHint()

        #expect(!session.isSwipeHintVisible)
        #expect(defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
        let (later, _, _) = InboxTestSupport.makeSession(defaults: defaults)
        #expect(!later.isSwipeHintVisible)
    }

    @Test func theFirstFiledSwipeTargetDismissesTheHint() async {
        let defaults = EphemeralInboxDefaults(didShowSwipeHint: false)
        let (session, _, _) = InboxTestSupport.makeSession(defaults: defaults)

        // A refused swipe (missing fields) taught nothing; a sheet target is not a swipe, and
        // Trash is a step-1 button rather than a gesture (STYLEGUIDE decision #12).
        await session.choose(.next)
        await session.choose(.waiting)
        session.cancelSheet()
        await session.choose(.trash)
        #expect(session.isSwipeHintVisible)

        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.someday)

        #expect(session.processed == 2)
        #expect(!session.isSwipeHintVisible)
        #expect(defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
    }

    @Test func aDeviceThatSawTheHintNeverShowsItAgain() {
        let (session, _, _) = InboxTestSupport.makeSession()
        #expect(!session.isSwipeHintVisible)
    }
}
