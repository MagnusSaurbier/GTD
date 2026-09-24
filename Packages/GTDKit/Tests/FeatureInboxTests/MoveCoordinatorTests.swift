import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// Dragging a row onto a category (E3): a drop that needs nothing moves the note at once; one
/// that needs more opens the inbox's action card, the defer-date sheet or the project picker,
/// and the note moves when that dialogue confirms — or stays put when it is cancelled.
@MainActor
struct MoveCoordinatorTests {

    private func make() -> (mover: MoveCoordinator, app: AppModel) {
        let snapshot = Fixtures.sampleSnapshot
        let backend = TestBackend(snapshot: snapshot)
        let app = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        return (MoveCoordinator(model: app), app)
    }

    private func action(_ app: AppModel, status: ActionStatus, where test: (Action) -> Bool = { _ in true }) -> Action {
        let visible = Rules.visibleActions(app.snapshot, today: Fixtures.today)
        return visible.first { $0.status == status && test($0) }!
    }

    // MARK: Straight moves

    @Test func aNextItemDroppedOnSomedayMovesAtOnce() async {
        let (mover, app) = make()
        let item = action(app, status: .next)
        #expect(mover.accepts(item.id, .someday))

        await mover.move(item.id, to: .someday)

        #expect(app.snapshot.action(item.id)?.status == .someday)
        #expect(mover.dialogue == nil)
    }

    @Test func droppingOnTheOwnSectionIsNotAccepted() async {
        let (mover, app) = make()
        let item = action(app, status: .next)
        #expect(!mover.accepts(item.id, .next))
        await mover.move(item.id, to: .next)
        #expect(app.snapshot.action(item.id)?.status == .next)
        #expect(mover.dialogue == nil)
    }

    @Test func anUnknownNoteIsNeverAccepted() {
        let (mover, _) = make()
        #expect(!mover.accepts(NoteID(path: "Actions/Nope.md"), .someday))
    }

    // MARK: The card

    /// A Someday item without Why/context/time dropped on Next: the same action card as the
    /// inbox, already marking exactly what Next still needs (R-3, STYLEGUIDE §3.6).
    @Test func anIncompleteItemDroppedOnNextOpensTheCardWithItsGapsMarked() async {
        let (mover, app) = make()
        let item = action(app, status: .someday) { $0.timeEstimate == nil }
        let missing = RequiredField.missing(
            status: .next, previous: .someday, why: item.why, what: item.what,
            contexts: item.contexts, timeEstimate: item.timeEstimate, followUpDate: nil)
        #expect(!missing.isEmpty)

        await mover.move(item.id, to: .next)

        guard case let .card(card)? = mover.dialogue else {
            Issue.record("expected the action card, got \(String(describing: mover.dialogue))")
            return
        }
        #expect(card.source == .action(item))
        #expect(card.draft.title == item.title)
        #expect(card.draft.what == item.what)
        #expect(card.missingFields == missing)
        #expect(card.sheet == nil)
        #expect(app.snapshot.action(item.id)?.status == .someday, "nothing moved yet")
    }

    /// Filling the card and swiping to Next moves the note — through `updateAction`, so the
    /// reducer's rules (fields, cap, project) apply exactly as to a filing.
    @Test func filingTheCardMovesTheNote() async {
        let (mover, app) = make()
        let item = action(app, status: .someday) { $0.timeEstimate == nil }
        await mover.move(item.id, to: .next)
        guard case let .card(card)? = mover.dialogue else { Issue.record("no card"); return }

        card.draft.why = "Because."
        if card.draft.what.isEmpty { card.draft.what = "Do it." }
        card.draft.contexts = [app.snapshot.config.contexts.first!]
        card.draft.timeBucket = .upTo30
        await card.take(.next)

        #expect(card.isFiled, "\(String(describing: card.refusal))")
        let moved = app.snapshot.action(item.id)
        #expect(moved?.status == .next)
        #expect(moved?.why == "Because.")
        #expect(moved?.timeEstimate == TimeBucket.upTo30.minutes)
    }

    /// Cancelling the card leaves the note exactly where it was.
    @Test func cancellingTheCardLeavesTheNoteAlone() async {
        let (mover, app) = make()
        let item = action(app, status: .someday) { $0.timeEstimate == nil }
        await mover.move(item.id, to: .next)
        #expect(mover.dialogue != nil)

        mover.cancel()

        #expect(mover.dialogue == nil)
        #expect(app.snapshot.action(item.id) == item)
    }

    /// W1/D39 — Waiting needs its follow-up date and nothing else from an existing action, so
    /// the card opens with the waiting sheet already up; confirming it moves the note.
    @Test func droppingOnWaitingOpensTheFollowUpSheetOverTheCard() async {
        let (mover, app) = make()
        let item = action(app, status: .next)

        await mover.move(item.id, to: .waiting)

        guard case let .card(card)? = mover.dialogue else { Issue.record("no card"); return }
        #expect(card.sheet == .waiting)
        #expect(card.missingFields == [.followUpDate])

        let followUp = Day(year: 2026, month: 10, day: 2)
        await card.confirmWaiting(WaitingInfo(who: "Len", followUp: followUp))

        #expect(card.isFiled, "\(String(describing: card.refusal))")
        let moved = app.snapshot.action(item.id)
        #expect(moved?.status == .waiting)
        #expect(moved?.followUpDate == followUp)
        #expect(moved?.waitingFor == "Len")
    }

    // MARK: Deferred

    @Test func droppingOnDeferredAsksForADateAndDefers() async {
        let (mover, app) = make()
        let item = action(app, status: .next) { $0.deferDate == nil }

        await mover.move(item.id, to: .deferred)
        guard case let .deferDate(asked)? = mover.dialogue else { Issue.record("no date sheet"); return }
        #expect(asked.id == item.id)

        let date = Day(year: 2026, month: 10, day: 5)
        await mover.confirmDefer(asked, date: date)

        #expect(mover.dialogue == nil)
        #expect(app.snapshot.action(item.id)?.deferDate == date)
        #expect(Rules.deferredList(app.snapshot, today: Fixtures.today).contains { $0.id == item.id })
    }

    // MARK: Projects

    @Test func droppingOnAProjectRowAttachesItReplacingTheOldOne() async {
        let (mover, app) = make()
        let project = app.snapshot.projects.first { $0.status == .active }!
        let item = action(app, status: .someday) { $0.project != project.id }

        await mover.move(item.id, to: .project(project.id))

        #expect(mover.dialogue == nil)
        #expect(app.snapshot.action(item.id)?.project == project.id)
        #expect(!mover.accepts(item.id, .project(project.id)), "already attached")
    }

    @Test func droppingOnTheProjectsSectionAsksWhichAndAttaches() async {
        let (mover, app) = make()
        let project = app.snapshot.projects.first { $0.status == .active }!
        let item = action(app, status: .someday) { $0.project != project.id }

        await mover.move(item.id, to: .projects)
        guard case let .pickProject(asked)? = mover.dialogue else { Issue.record("no picker"); return }
        #expect(asked.id == item.id)
        #expect(mover.projectPicker().groups.flatMap(\.projects).contains { $0.id == project.id })

        await mover.chooseProject(asked, project.id)

        #expect(mover.dialogue == nil)
        #expect(app.snapshot.action(item.id)?.project == project.id)
    }

    /// R-8 — the picker's create row: the project is born by its own command, then attached.
    @Test func creatingAProjectFromThePickerAttachesTheNewOne() async {
        let (mover, app) = make()
        let item = action(app, status: .someday)
        await mover.move(item.id, to: .projects)
        guard case let .pickProject(asked)? = mover.dialogue else { Issue.record("no picker"); return }

        await mover.createProject(asked, named: "Ungarn-Tour planen")

        let attached = app.snapshot.action(item.id)?.project
        #expect(attached != nil)
        #expect(app.snapshot.projects.contains { $0.id == attached && $0.title == "Ungarn-Tour planen" })
    }
}
