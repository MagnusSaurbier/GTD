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
        await session.choose(.backlog)

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

    @Test func titleIsDerivedFromWhatAndStaysEditable() {
        let (session, _, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)

        // Empty What? falls back to the captured text.
        #expect(session.draft.effectiveTitle == item.text)

        session.draft.what = "- [ ] Ring the Hausverwaltung\n- [ ] Note the case number"
        #expect(session.draft.effectiveTitle == "Ring the Hausverwaltung")
        #expect(session.draft.suggestsProject)   // A2: two checkboxes

        session.draft.title = "Window handle"
        session.draft.titleWasEdited = true
        #expect(session.draft.effectiveTitle == "Window handle")
    }

    @Test func filingWritesExactlyWhatTheDraftHolds() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.why = "The window does not close."
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls", "home"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Fixtures.day(3)

        await session.choose(.backlog)

        let action = try! #require(model.snapshot.actions.first { $0.title == "Ring the Hausverwaltung" })
        #expect(action.status == .backlog)
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

    @Test func nextAndBacklogRequireAWhat() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        let actionsBefore = model.snapshot.actions.count

        await session.choose(.next)
        #expect(session.validation?.issue == .whatRequired)
        #expect(session.current?.id == item.id)
        #expect(model.snapshot.actions.count == actionsBefore)

        let firstNonce = try! #require(session.validation?.nonce)
        await session.choose(.backlog)
        #expect(session.validation?.issue == .whatRequired)
        #expect(session.validation?.nonce == firstNonce + 1)   // shakes again
        #expect(model.snapshot.actions.count == actionsBefore)
    }

    @Test func maybeAndTrashDoNotNeedAWhat() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        await session.choose(.maybe)
        #expect(session.validation == nil)
        #expect(session.processed == 1)
        #expect(model.snapshot.actions.contains { $0.status == .maybe && $0.why.isEmpty })

        await session.choose(.trash)
        #expect(session.processed == 2)
    }

    @Test func contextsAndTimeMayStayEmpty() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.backlog)

        let action = try! #require(model.snapshot.actions.first { $0.title == "Ring the Hausverwaltung" })
        #expect(action.contexts.isEmpty)
        #expect(action.timeEstimate == nil)   // never 0 (§1)
    }

    // MARK: - Cap (A3, I4, ARCHITECTURE §6)

    @Test func capOffersAForcedChoiceAndKeepsTheDraft() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let cap = model.snapshot.config.nextCap
        #expect(Rules.countsTowardCap(model.snapshot) == cap - 1)

        // One slot left: the first card fits.
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.next)
        #expect(Rules.countsTowardCap(model.snapshot) == cap)
        #expect(session.sheet == nil)

        // The next one is refused — the card stays, with everything the user typed.
        let refused = try! #require(session.current)
        session.draft.what = "Write the rename script"
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
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.next)
        session.draft.what = "Write the rename script"
        await session.choose(.next)
        #expect(session.sheet == .cap)

        let victim = try! #require(session.capCandidates.first)
        await session.demoteAndRetry(victim.id)

        #expect(session.sheet == nil)
        #expect(model.snapshot.action(victim.id)?.status == .backlog)
        let filed = try! #require(model.snapshot.actions.first { $0.title == "Write the rename script" })
        #expect(filed.status == .next)
        #expect(Rules.countsTowardCap(model.snapshot) == cap)
        #expect(session.processed == 2)
    }

    @Test func sendToBacklogInsteadIsTheOtherHalfOfTheChoice() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let cap = model.snapshot.config.nextCap
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.next)
        session.draft.what = "Write the rename script"
        await session.choose(.next)
        #expect(session.sheet == .cap)

        await session.sendToBacklogInstead()

        #expect(session.sheet == nil)
        let filed = try! #require(model.snapshot.actions.first { $0.title == "Write the rename script" })
        #expect(filed.status == .backlog)
        #expect(Rules.countsTowardCap(model.snapshot) == cap)   // nothing was demoted behind the user's back
        #expect(session.processed == 2)
    }

    @Test func cancellingTheCapSheetLeavesTheCardWhereItIs() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.next)
        let refused = try! #require(session.current)
        session.draft.what = "Write the rename script"
        await session.choose(.next)

        session.cancelSheet()

        #expect(session.sheet == nil)
        #expect(session.current?.id == refused.id)
        #expect(session.draft.what == "Write the rename script")
        #expect(model.snapshot.inboxItem(refused.id) != nil)
    }

    /// The cap also guards the project sub-flow, and "Backlog instead" demotes the first actions.
    @Test func capAppliesToProjectFirstActionsToo() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.what = "Ring the Hausverwaltung"
        await session.choose(.next)   // now at the cap

        let project = try! #require(model.snapshot.projects.first { $0.status == .active })
        await session.confirmExistingProject(
            project.id,
            actions: [ActionDraft(title: "Collect the forms", status: .next, what: "Collect the forms")])
        #expect(session.sheet == .cap)

        await session.sendToBacklogInstead()
        let filed = try! #require(model.snapshot.actions.first { $0.title == "Collect the forms" })
        #expect(filed.status == .backlog)
        #expect(filed.project == project.id)
    }

    // MARK: - Sub-flows (I4, I5, W1)

    @Test func knowledgeFilesTheCaptureAndRemembersTheFolder() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        #expect(session.suggestedKnowledgeFolder == nil)   // nothing is suggested on a fresh device

        await session.confirmKnowledge(folder: "Studium/Thesis", title: "Window handle notes")

        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.suggestedKnowledgeFolder == "Studium/Thesis")
        #expect(session.processed == 1)
        #expect(session.sheet == nil)
    }

    @Test func knowledgeSuggestsTheLastUsedFolder() {
        let (session, _, _) = InboxTestSupport.makeSession(lastKnowledgeFolder: "Technik")
        #expect(session.suggestedKnowledgeFolder == "Technik")
    }

    @Test func knowledgeNeedsATitle() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.confirmKnowledge(folder: "Technik", title: "   ")
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(session.processed == 0)
    }

    @Test func waitingNeedsWhoAndFollowUpAndWritesBoth() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.what = "Monitor for Marie"
        let followUp = WaitingInfo.suggestedFollowUp(from: Fixtures.today)

        await session.confirmWaiting(WaitingInfo(who: "Marie", followUp: followUp))

        let action = try! #require(model.snapshot.actions.first { $0.title == "Monitor for Marie" })
        #expect(action.status == .waiting)
        #expect(action.waitingFor == "Marie")
        #expect(action.followUpDate == followUp)
        #expect(followUp == Fixtures.today.adding(days: 7))   // W1's +7 d, confirmed by the user
    }

    @Test func newProjectCreatesProjectAreaAndFirstActions() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let areasBefore = model.snapshot.areas.count

        await session.confirmNewProject(
            ProjectDraft(
                title: "Fix the flat",
                newAreaTitle: "Haushalt",
                outcome: "Everything in the flat works again",
                why: "Living with broken things costs energy"),
            firstActions: [
                ActionDraft(title: "Ring the Hausverwaltung", status: .next,
                            contexts: ["calls"], what: "Ring the Hausverwaltung"),
            ])

        #expect(model.snapshot.areas.count == areasBefore + 1)
        let project = try! #require(model.snapshot.projects.first { $0.title == "Fix the flat" })
        #expect(project.outcome == "Everything in the flat works again")
        let action = try! #require(model.snapshot.actions.first { $0.title == "Ring the Hausverwaltung" })
        #expect(action.project == project.id)
        #expect(action.status == .next)
        #expect(session.processed == 1)
    }

    @Test func existingProjectLinksTheActionToIt() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let project = try! #require(model.snapshot.projects.first { $0.title == "DAAD" })

        await session.confirmExistingProject(
            project.id,
            actions: [ActionDraft(title: "Collect the forms", status: .backlog, what: "Collect the forms")])

        let action = try! #require(model.snapshot.actions.first { $0.title == "Collect the forms" })
        #expect(action.project == project.id)
        #expect(session.processed == 1)
    }

    /// P3 — a first action for a project that is not active goes to Backlog, not Next.
    @Test func firstActionStatusFollowsTheProjectStatus() {
        let (session, model, _) = InboxTestSupport.makeSession()
        let active = try! #require(model.snapshot.projects.first { $0.status == .active })
        let onHold = try! #require(model.snapshot.projects.first { $0.status != .active })

        #expect(ProjectPicker.statusForFirstAction(in: active) == .next)
        #expect(ProjectPicker.statusForFirstAction(in: onHold) == .backlog)
        #expect(ProjectPicker.statusForFirstAction(in: nil) == .backlog)

        session.draft.what = "Collect the forms"
        #expect(session.firstActionDraft(for: active).project == active.id)
        #expect(session.firstActionDraft(for: active).status == .next)
        #expect(session.firstActionDraft(for: onHold).status == .backlog)
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

        await session.choose(.backlog)
        #expect(session.current?.id != item.id)
        #expect(session.processed == 1)
        #expect(session.canUndo)

        await session.undo()

        #expect(session.current?.id == item.id)
        #expect(session.draft == filed)
        #expect(session.processed == 0)
        #expect(model.snapshot.inboxItem(item.id) != nil)
        #expect(!model.snapshot.actions.contains { $0.title == "Ring the Hausverwaltung" })
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
        await session.choose(.backlog)
        #expect(session.undoToastLabel == "Moved to Backlog")   // STYLEGUIDE §6.3

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
        await session.choose(.backlog)
        await session.choose(.trash)

        #expect(session.isFinished)
        #expect(session.current == nil)
        #expect(session.processed == 2)
        let counts = Dictionary(uniqueKeysWithValues: session.summaryCounts.map { ($0.target, $0.count) })
        #expect(counts[.backlog] == 1)
        #expect(counts[.trash] == 1)
        #expect(counts[.next] == 0)
        #expect(InboxCopy.targetBreakdown(session.summaryCounts) == "1 Backlog · 1 Trash")
        #expect(session.elapsedMinutes == 0)
    }

    @Test func draftResetsForTheNextCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.draft.why = "because"
        session.draft.what = "Ring the Hausverwaltung"
        session.draft.contexts = ["calls"]
        await session.choose(.backlog)

        let next = try! #require(session.current)
        #expect(session.draft.isPristine(for: next))
        #expect(session.draft.text == next.text)
    }
}
