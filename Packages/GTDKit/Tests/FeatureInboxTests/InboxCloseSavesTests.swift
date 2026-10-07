import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// #85 — "clicking close on a half-processed inbox file erases the progress." Leaving the
/// session keeps the card in its inbox note (`InboxSession.saveProgress()`), which stays in the
/// inbox; the next session opens it as it was left. Also the Knowledge sheet's notes, the crash
/// journal, `Defer to review`, and the "Make action" card over an existing action.
@MainActor
struct InboxCloseSavesTests {

    private func typeHalfACard(_ session: InboxSession) {
        session.draft.why = "The handle has been broken for two weeks."
        session.draft.what = "- [ ] call them"
        session.draft.contexts = ["calls"]
        session.draft.timeBucket = .upTo10
        session.draft.due = Day(year: 2026, month: 9, day: 30)
    }

    @Test func closingKeepsTheCardInItsNoteAndInTheInbox() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let id = try #require(session.current?.id)
        typeHalfACard(session)
        #expect(session.hasUnsavedProgress)

        await session.saveProgress()

        let stored = try #require(model.snapshot.inboxItem(id))
        #expect(InboxBody.read(stored.body).why == "The handle has been broken for two weeks.")
        #expect(InboxBody.read(stored.body).what == "- [ ] call them")
        #expect(stored.contexts == ["calls"])
        #expect(stored.timeEstimate == 10)
        #expect(stored.due == Day(year: 2026, month: 9, day: 30))
        #expect(Rules.inboxQueue(model.snapshot).contains { $0.id == id }, "not processed")
        #expect(model.snapshot.actions.allSatisfy { $0.title != id.title })
        #expect(!session.hasUnsavedProgress)
        #expect(model.lastError == nil)
    }

    /// The next session opens the card with everything it was closed with.
    @Test func theNextSessionOpensTheCardAsItWasLeft() async throws {
        let (session, model, backend) = await InboxTestSupport.openedActionCard()
        typeHalfACard(session)
        let draft = session.draft
        await session.saveProgress()

        let next = InboxSession(
            model: model, defaults: EphemeralInboxDefaults(), now: { Fixtures.date(Fixtures.today, 11, 0) })
        #expect(next.draft == draft)
        #expect(next.step == .step1)
        _ = backend
    }

    @Test func anUntouchedCardWritesNothing() async {
        let (session, _, backend) = InboxTestSupport.makeSession()
        #expect(!session.hasUnsavedProgress)
        await session.saveProgress()
        #expect(backend.commands.isEmpty)
    }

    /// A collapse keeps the draft (STYLEGUIDE §3.6), so closing from step 1 still keeps it.
    @Test func closingAfterACollapseStillKeepsTheFields() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let id = try #require(session.current?.id)
        session.draft.what = "call them"
        session.collapse()
        #expect(session.escape() == .quit)
        await session.saveProgress()
        #expect(InboxBody.read(try #require(model.snapshot.inboxItem(id)).body).what == "call them")
    }

    @Test func aChangedTitleRenamesTheNoteAfterTheBodyIsKept() async throws {
        let (session, model, backend) = InboxTestSupport.makeSession()
        let id = try #require(session.current?.id)
        session.draft.title = "Hausverwaltung window"
        session.draft.body = "typed on step 1"
        await session.saveProgress()

        let renamed = model.snapshot.config.layout.inboxPath(title: "Hausverwaltung window")
        #expect(model.snapshot.inboxItem(id) == nil)
        #expect(model.snapshot.inboxItem(renamed)?.body == "typed on step 1")
        #expect(session.current?.id == renamed, "the session follows the rename")
        guard case .saveInboxProgress = backend.commands.first else {
            Issue.record("the body is written before the rename: \(backend.commands)")
            return
        }
    }

    /// A taken name refuses the rename — the alert says so — but never costs the text.
    @Test func aRefusedRenameStillKeepsTheText() async throws {
        let (session, model, _) = InboxTestSupport.makeSession()
        let id = try #require(session.current?.id)
        let other = try #require(session.queue.dropFirst().first)
        session.draft.title = other.title
        session.draft.why = "kept anyway"
        await session.saveProgress()

        #expect(model.lastError as? GTDError == .titleCollision(other.title))
        #expect(InboxBody.read(try #require(model.snapshot.inboxItem(id)).body).why == "kept anyway")
    }

    /// A blank title is not a name: the note keeps its own and nothing is refused.
    @Test func aBlankTitleIsNotARename() async throws {
        let (session, model, _) = InboxTestSupport.makeSession()
        let id = try #require(session.current?.id)
        session.draft.title = "   "
        session.draft.what = "call"
        await session.saveProgress()
        #expect(model.lastError == nil)
        #expect(model.snapshot.inboxItem(id) != nil)
    }

    @Test func twoSavesInARowWriteOnce() async throws {
        let (session, _, backend) = await InboxTestSupport.openedActionCard()
        session.draft.title = "renamed once"
        session.draft.why = "x"
        async let one: Void = session.saveProgress()
        async let two: Void = session.saveProgress()
        _ = await (one, two)
        let renames = backend.commands.filter { if case .renameInboxItem = $0 { true } else { false } }
        #expect(renames.count == 1)
    }

    /// The Knowledge / List card's notes have no slot of their own in an inbox note: they join
    /// the capture text, where a Knowledge filing would have put them.
    @Test func notesJoinTheCaptureText() async throws {
        let (session, model, _) = InboxTestSupport.makeSession()
        let id = try #require(session.current?.id)
        session.draft.notes = "from the keep card"
        await session.saveProgress()
        #expect(try #require(model.snapshot.inboxItem(id)).body.contains("from the keep card"))
    }

    /// `Defer to review` keeps the card's fields in the note it leaves in the inbox.
    @Test func deferToReviewKeepsTheCard() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let id = try #require(session.current?.id)
        session.draft.why = "half a thought"
        session.draft.contexts = ["calls"]
        session.collapse()
        await session.confirmDeferToReview(reason: "no idea yet")

        let stored = try #require(model.snapshot.inboxItem(id))
        #expect(stored.reviewReason == "no idea yet")
        #expect(InboxBody.read(stored.body).why == "half a thought")
        #expect(stored.contexts == ["calls"])
    }

    /// L1 — a list item carries nothing but its notes: chips a closed card left behind are
    /// cleared before the note moves into `Lists/`.
    @Test func filingToAListClearsTheChipsFirst() async throws {
        let (session, model, backend) = InboxTestSupport.makeSession()
        let id = try #require(session.current?.id)
        session.draft.contexts = ["calls"]
        await session.saveProgress()
        let fresh = InboxSession(
            model: model, defaults: EphemeralInboxDefaults(), now: { Fixtures.date(Fixtures.today, 11, 0) })
        #expect(fresh.current?.id == id)

        await fresh.take(.openKeep)
        await fresh.take(.list("Read"))

        let clearing = backend.commands.last { if case .saveInboxProgress = $0 { true } else { false } }
        guard case let .saveInboxProgress(_, progress) = clearing else {
            Issue.record("no progress write: \(backend.commands)")
            return
        }
        #expect(progress.contexts.isEmpty)
        #expect(model.snapshot.inboxItem(id) == nil, "filed")
    }

    /// A body that holds only the card's sections shows no body field on step 1.
    @Test func stepOneShowsOnlyTheCaptureText() async throws {
        let (session, model, _) = InboxTestSupport.makeSession()
        session.draft.why = "kept"
        await session.saveProgress()
        let fresh = InboxSession(
            model: model, defaults: EphemeralInboxDefaults(), now: { Fixtures.date(Fixtures.today, 11, 0) })
        #expect(fresh.draft.why == "kept")
        #expect(fresh.draft.body.isEmpty, "the sample capture's title held all of its text")
        #expect(!fresh.showsBody, "the stored body is only the card's Why?")
    }

    // MARK: - The app stopping (#56)

    @Test func quittingKeepsTheCardLikeClosing() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let id = try #require(session.current?.id)
        session.draft.what = "call"
        await model.flushHeldEdits()
        #expect(InboxBody.read(try #require(model.snapshot.inboxItem(id)).body).what == "call")
    }

    @Test func theCrashJournalSeesTheTypedCard() async throws {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let id = try #require(session.current?.id)
        #expect(session.unsavedText == nil)

        session.draft.why = "typed"
        let entry = try #require(session.unsavedText)
        #expect(entry.kind == .inbox)
        #expect(entry.path == id.path)
        #expect(entry.title == nil)
        #expect(entry.restoreCommand(in: model.snapshot) == .editInboxBody(id, try #require(entry.text)))

        await session.saveProgress()
        #expect(session.unsavedText == nil)
    }

    // MARK: - "Make action" over an existing action

    private func actionCard() throws -> (MakeActionModel, AppModel, Action) {
        let snapshot = Fixtures.sampleSnapshot
        let backend = TestBackend(snapshot: snapshot)
        let app = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        let action = try #require(snapshot.actions.first { $0.status == .someday })
        return (MakeActionModel(model: app, action: action, target: .next, missing: [.why]), app, action)
    }

    @Test func closingTheMoveCardKeepsTheTypedFieldsButNotTheMove() async throws {
        let (card, app, action) = try actionCard()
        card.draft.why = "Typed on the card"
        card.draft.contexts = ["calls"]
        card.cancel()
        await card.keepEdits()

        let kept = try #require(app.snapshot.action(action.id))
        #expect(kept.why == "Typed on the card")
        #expect(kept.contexts == ["calls"])
        #expect(kept.status == action.status, "only the move is cancelled")
        #expect(card.keptEdits == nil, "a second close writes nothing")
    }

    @Test func anUntouchedMoveCardWritesNothing() throws {
        let (card, _, _) = try actionCard()
        #expect(card.keptEdits == nil)
    }

    @Test func aListItemCardKeepsNothing() throws {
        let snapshot = Fixtures.sampleSnapshot
        let app = AppModel(backend: TestBackend(snapshot: snapshot), snapshot: snapshot, today: { Fixtures.today })
        let item = try #require(snapshot.listItems.first { !$0.isFinished })
        let card = MakeActionModel(model: app, item: item)
        card.draft.why = "typed"
        #expect(card.keptEdits == nil)
    }
}
