import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// #94 — the dialogs #85 left: what is typed is kept in `InputDrafts` and comes back when the
/// same dialog opens again; the main button clears it once it went through, `Cancel` clears it
/// (that half lives in the views).
@MainActor
struct DialogDraftsTests {

    private func app(_ snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        AppModel(backend: TestBackend(snapshot: snapshot), snapshot: snapshot, today: { Fixtures.today })
    }

    private func typeFields(_ card: MakeActionModel) {
        card.draft.why = "Because."
        card.draft.what = "Read the first chapter"
        card.draft.contexts = ["home"]
        card.draft.timeBucket = .upTo30
    }

    // MARK: Make action over a note without action fields

    @Test func makeActionOverAListItemKeepsWhatWasTypedForTheNextCard() throws {
        let app = app()
        let item = try #require(app.snapshot.listItems.first { !$0.isFinished })
        let first = MakeActionModel(model: app, item: item)
        typeFields(first)
        let typed = first.draft
        #expect(app.inputDrafts.hasDraft(for: InputDraftKey.makeActionOverListItem(item.id)))

        // The card was closed without filing (`Close`, `Esc`, a swipe): a new one comes back.
        let reopened = MakeActionModel(model: app, item: item)
        #expect(reopened.draft == typed)
        #expect(app.snapshot.listItem(item.id)?.notes == item.notes, "nothing written to the note")

        // Another list item starts from its own values.
        let other = try #require(app.snapshot.listItems.first { !$0.isFinished && $0.id != item.id })
        #expect(MakeActionModel(model: app, item: other).draft == InboxDraft(item: other))
    }

    @Test func undoingEveryChangeKeepsNoDraft() throws {
        let app = app()
        let item = try #require(app.snapshot.listItems.first { !$0.isFinished })
        let card = MakeActionModel(model: app, item: item)
        card.draft.why = "Because."
        card.draft.why = ""
        #expect(!app.inputDrafts.hasDraft(for: InputDraftKey.makeActionOverListItem(item.id)))
    }

    @Test func filingTheCardClearsItsDraft() async throws {
        let app = app()
        let item = try #require(app.snapshot.listItems.first { !$0.isFinished })
        let card = MakeActionModel(model: app, item: item)
        typeFields(card)
        await card.take(.someday)
        #expect(card.isFiled)
        #expect(!app.inputDrafts.hasDraft(for: InputDraftKey.makeActionOverListItem(item.id)))
    }

    @Test func aProjectStepAndAWhatsNextLineKeepTheirDraftsByText() throws {
        let app = app()
        let project = try #require(app.snapshot.projects.first)
        let step = MakeActionModel(model: app, project: project.id, stepIndex: 0, stepText: "Ask Marie")
        step.draft.why = "She knows."
        // The same step (by text) at another index finds it; another step does not.
        #expect(MakeActionModel(model: app, project: project.id, stepIndex: 3, stepText: "Ask Marie").draft.why
                == "She knows.")
        #expect(MakeActionModel(model: app, project: project.id, stepIndex: 0, stepText: "Other").draft.why.isEmpty)

        let line = MakeActionModel(model: app, project: project.id, newActionTitle: "Book a room")
        line.draft.contexts = ["calls"]
        #expect(MakeActionModel(model: app, project: project.id, newActionTitle: "Book a room").draft.contexts
                == ["calls"])
    }

    /// Over an existing action the edits go into the action itself (#85), not into a draft.
    @Test func overAnExistingActionThereIsNoDraftOnlyTheFollowUpSheetsKey() throws {
        let app = app()
        let action = try #require(app.snapshot.actions.first)
        let card = MakeActionModel(model: app, changingStatusOf: action)
        #expect(card.draftKey == nil)
        #expect(card.waitingDraftKey == InputDraftKey.waiting(action.id))
        card.draft.why = "changed"
        #expect(!app.inputDrafts.hasDraft(for: InputDraftKey.makeActionOverListItem(action.id)))
    }

    // MARK: Inbox sub-sheets

    @Test func settingWaitingClearsTheFollowUpSheetsDraftOnlyOnceFiled() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let key = try #require(session.waitingDraftKey)
        model.inputDrafts.keep(WaitingSheetDraft(who: "Marie"), for: key)
        let followUp = WaitingInfo.suggestedFollowUp(from: Fixtures.today)

        await session.confirmWaiting(WaitingInfo(who: "Marie", followUp: followUp))
        #expect(session.refusal?.reason == .missing([.what]))
        #expect(model.inputDrafts.value(WaitingSheetDraft.self, for: key)?.who == "Marie", "refused: kept")

        session.draft.what = "Monitor for Marie"
        await session.confirmWaiting(WaitingInfo(who: "Marie", followUp: followUp))
        #expect(session.processed == 1)
        #expect(!model.inputDrafts.hasDraft(for: key))
    }

    @Test func deferringClearsTheReasonDraftARefusalKeepsIt() async throws {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try #require(session.current)
        let key = try #require(session.deferReasonDraftKey)
        #expect(key == InputDraftKey.deferReason(item.id))
        model.inputDrafts.keep("It is a decision", for: key)

        await session.take(.openAction)
        await session.confirmDeferToReview(reason: "It is a decision")    // not from the card
        #expect(model.inputDrafts.hasDraft(for: key))

        session.collapse()
        await session.confirmDeferToReview(reason: "It is a decision")
        #expect(model.snapshot.inboxItem(item.id)?.reviewReason == "It is a decision")
        #expect(!model.inputDrafts.hasDraft(for: key))
    }

    @Test func creatingAListClearsThePickersNameDraftARefusalKeepsIt() async throws {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.lists = []
        snapshot.listItems = []
        snapshot.config.favouriteLists = nil
        let (session, model, _) = InboxTestSupport.makeSession(snapshot: snapshot)
        await session.take(.openKeep)
        await session.take(.more)
        model.inputDrafts.keep("Read", for: InputDraftKey.newListInPicker)

        #expect(await session.createListAndFile(name: "   ") == false)
        #expect(model.inputDrafts.hasDraft(for: InputDraftKey.newListInPicker))

        #expect(await session.createListAndFile(name: "Read"))
        #expect(!model.inputDrafts.hasDraft(for: InputDraftKey.newListInPicker))
    }

    @Test func creatingAListFromADropClearsThePickersNameDraft() async throws {
        let app = app()
        let mover = MoveCoordinator(model: app)
        let item = try #require(Rules.visibleActions(app.snapshot, today: Fixtures.today).first { $0.status == .someday })
        await mover.move(item.id, to: .lists)
        guard case let .pickList(asked)? = mover.dialogue else { Issue.record("no list picker"); return }
        app.inputDrafts.keep("Gifts", for: InputDraftKey.newListInPicker)

        #expect(await mover.createListAndMove(asked, named: "   ") == false)
        #expect(app.inputDrafts.hasDraft(for: InputDraftKey.newListInPicker))
        #expect(await mover.createListAndMove(asked, named: "Gifts"))
        #expect(!app.inputDrafts.hasDraft(for: InputDraftKey.newListInPicker))
    }
}
