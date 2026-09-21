import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureOverview

/// The dangerous part of T25: debounced autosave must not lose an edit, must not clobber a
/// snapshot that arrives mid-edit, and must follow the `NoteID` a rename creates.
///
/// The debounce is injected: a sleep that returns immediately but honours cancellation, so
/// coalescing is tested deterministically and without wall-clock time.
@MainActor
struct ActionEditModelTests {

    /// Returns at once, but a task that was superseded still throws out of it.
    private static let instantSleep: ActionEditModel.Sleep = { _ in
        try Task.checkCancellation()
    }

    private func fixture(
        title: String = "Draft action",
        status: ActionStatus = .someday,
        why: String = "old why",
        what: String = "old what"
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"),
            title: title,
            status: status,
            contexts: ["mac"],
            why: why,
            what: what)
    }

    private func make(
        _ action: Action,
        snapshot base: VaultSnapshot = Fixtures.sampleSnapshot
    ) -> (AppModel, ActionEditModel) {
        var snapshot = base
        snapshot.actions.append(action)
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                     env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
        let editor = ActionEditModel(
            model: model, id: action.id, debounce: .milliseconds(1), sleep: Self.instantSleep)
        return (model, editor)
    }

    // MARK: - Debounce

    @Test func typingCoalescesIntoOneSave() async {
        let (model, editor) = make(fixture())
        editor.setWhy("a")
        editor.setWhy("ab")
        editor.setWhy("abc")
        #expect(editor.hasUnsavedEdits)

        await editor.waitForPendingSave()

        #expect(model.snapshot.action(editor.id)?.why == "abc")
        #expect(editor.hasUnsavedEdits == false)
        #expect(editor.lastError == nil)
    }

    /// The app's configuration (no debounce): typing never writes. The text goes to the vault
    /// when the field blurs or the editor closes (`flush()`), or when the shell says the app is
    /// about to stop running (`AppModel.flushHeldEdits()`); a chip tap still saves at once.
    @Test func typedTextIsHeldUntilANaturalMomentButAChipSavesAtOnce() async throws {
        let (model, _) = make(fixture())
        let id = fixture().id
        let editor = ActionEditModel(model: model, id: id)

        editor.setWhy("typed")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(model.snapshot.action(id)?.why == "old why", "no timer wrote it")
        #expect(editor.hasUnsavedEdits)

        await model.flushHeldEdits()
        #expect(model.snapshot.action(id)?.why == "typed")

        editor.setContexts(["phone"])
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(id)?.contexts == ["phone"])
    }

    @Test func flushWritesImmediately() async {
        let (model, editor) = make(fixture())
        editor.setWhat("- [ ] one")
        await editor.flush()
        #expect(model.snapshot.action(editor.id)?.what == "- [ ] one")
    }

    @Test func nothingIsWrittenWithoutAnEdit() async {
        let (model, editor) = make(fixture())
        let before = model.snapshot
        await editor.flush()
        #expect(model.snapshot == before)
    }

    // MARK: - Risk 1: a snapshot arriving mid-edit

    /// The user is typing in `Why?` while the vault changes `What?` (sync, another device, a
    /// command from another view). Neither side may lose its value.
    @Test func aSnapshotArrivingMidEditClobbersNeitherSide() async throws {
        let action = fixture()
        let (model, editor) = make(action)

        // 1. The user types — not yet saved.
        editor.setWhy("my new why")

        // 2. Something else rewrites a *different* field of the same note.
        var remote = try #require(model.snapshot.action(action.id))
        remote.what = "- [ ] remote what"
        try await model.send(.updateAction(remote))
        editor.refresh()

        // The editor shows the user's text *and* the remote change.
        #expect(editor.why == "my new why")
        #expect(editor.what == "- [ ] remote what")

        // 3. The debounced save lands: it writes only the edited field.
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.why == "my new why")
        #expect(saved.what == "- [ ] remote what")     // NOT reverted to the stale draft
        #expect(editor.hasUnsavedEdits == false)
    }

    /// An untouched field keeps following the vault; a touched one does not jump back.
    @Test func refreshAdoptsRemoteValuesOnlyForUntouchedFields() async throws {
        let action = fixture()
        let (model, editor) = make(action)
        editor.setWhy("local why")

        var remote = try #require(model.snapshot.action(action.id))
        remote.why = "remote why"
        remote.what = "remote what"
        try await model.send(.updateAction(remote))
        editor.refresh()

        #expect(editor.why == "local why")
        #expect(editor.what == "remote what")
    }

    /// An edit made while the save is in flight survives it: it stays dirty and is written next.
    @Test func anEditDuringAnInFlightSaveIsNotDropped() async {
        let (model, editor) = make(fixture())
        editor.setWhy("first")
        let save = Task { await editor.waitForPendingSave() }
        await Task.yield()                       // let the first save start
        editor.setWhy("second")
        await save.value
        await editor.waitForPendingSave()

        #expect(editor.why == "second")
        #expect(model.snapshot.action(editor.id)?.why == "second")
        #expect(editor.hasUnsavedEdits == false)
    }

    // MARK: - Risk 2: a rename changes the NoteID

    @Test func renameFollowsTheNewNoteID() async throws {
        let action = fixture(title: "Old title")
        let (model, editor) = make(action)
        var renamed: NoteID?
        editor.onRename = { renamed = $0 }

        editor.setTitle("New title")
        await editor.waitForPendingSave()

        let expected = model.snapshot.config.layout.actionPath(title: "New title")
        #expect(editor.id == expected)
        #expect(renamed == expected)
        #expect(editor.isMissing == false)
        #expect(model.snapshot.action(action.id) == nil)
        #expect(model.snapshot.action(expected)?.title == "New title")
    }

    /// The real failure mode: after a rename the *next* edit must still find the note.
    @Test func editingContinuesAfterARename() async throws {
        let (model, editor) = make(fixture(title: "Old title"))
        editor.setTitle("Renamed once")
        await editor.waitForPendingSave()

        editor.setWhy("still editing")
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.title == "Renamed once")
        #expect(saved.why == "still editing")
        #expect(editor.lastError == nil)
        #expect(model.snapshot.actions.count { $0.title == "Renamed once" } == 1)
    }

    /// A rename typed in one go debounces to a single move — no intermediate files.
    @Test func typingATitleRenamesOnlyOnce() async {
        let (model, editor) = make(fixture(title: "Old title"))
        editor.setTitle("N")
        editor.setTitle("Ne")
        editor.setTitle("New")
        await editor.waitForPendingSave()

        #expect(editor.id.title == "New")
        #expect(model.snapshot.actions.count { $0.title == "N" || $0.title == "Ne" } == 0)
    }

    @Test func renameCollidingWithAnExistingTitleIsRefusedAndKeepsTheText() async throws {
        let existing = fixture(title: "Taken")
        var snapshot = Fixtures.sampleSnapshot
        snapshot.actions.append(existing)
        let (model, editor) = make(fixture(title: "Mine"), snapshot: snapshot)

        editor.setTitle("Taken")
        await editor.waitForPendingSave()

        #expect(editor.lastError != nil)
        #expect(editor.title == "Taken")                    // the user's text is not thrown away
        #expect(editor.id == NoteID(path: "Actions/Mine.md"))
        #expect(model.snapshot.action(editor.id)?.title == "Mine")
        #expect(editor.hasUnsavedEdits)
    }

    // MARK: - Refused commands

    /// A3/I4 — the cap refuses the promotion; the refusal is reported, not retried forever.
    @Test func aRefusedStatusChangeSurfacesTheError() async throws {
        var snapshot = Fixtures.sampleSnapshot
        // The sample vault sits one below the cap; fill the last slot.
        snapshot.actions.append(fixture(title: "Fills the cap", status: .next))
        let (model, editor) = make(fixture(title: "One too many"), snapshot: snapshot)
        #expect(Rules.isAtCap(model.snapshot, today: Fixtures.today))

        editor.setStatus(.next)
        await editor.waitForPendingSave()

        #expect(editor.lastError is GTDError)
        #expect(model.snapshot.action(editor.id)?.status == .someday)
        #expect(editor.hasUnsavedEdits)

        // It does not hammer the backend: a repeated save without a new edit does nothing.
        editor.clearError()
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(editor.id)?.status == .someday)
    }

    /// W1 — waiting is only ever written together with who and a follow-up date.
    @Test func waitingIsWrittenWithWhoAndFollowUp() async throws {
        let (model, editor) = make(fixture())
        editor.setWaiting(WaitingInfo(who: "Lena", followUp: Fixtures.day(7)))
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.status == .waiting)
        #expect(saved.waitingFor == "Lena")
        #expect(saved.followUpDate == Fixtures.day(7))
        #expect(editor.lastError == nil)
    }

    @Test func leavingWaitingClearsWhoAndFollowUp() async throws {
        let (model, editor) = make(fixture())
        editor.setWaiting(WaitingInfo(who: "Lena", followUp: Fixtures.day(7)))
        await editor.waitForPendingSave()

        editor.setStatus(.someday)
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.status == .someday)
        #expect(saved.waitingFor == nil)
        #expect(saved.followUpDate == nil)
    }

    // MARK: - Gone notes

    @Test func aNoteThatLeftTheVaultIsReportedMissing() async throws {
        let action = fixture()
        let (model, editor) = make(action)
        try await model.send(.complete(action.id))
        var snapshot = model.snapshot
        snapshot.actions.removeAll { $0.id == action.id }
        // Simulate the note leaving the snapshot entirely (archived, trashed elsewhere).
        let gone = AppModel(
            backend: InMemoryBackend(snapshot: snapshot), snapshot: snapshot,
            today: { Fixtures.today })
        let orphan = ActionEditModel(
            model: gone, id: action.id, debounce: .milliseconds(1), sleep: Self.instantSleep)

        #expect(orphan.isMissing)
        #expect(orphan.draft == nil)
        orphan.setWhy("typing into the void")           // must not crash, must not write
        await orphan.waitForPendingSave()
        #expect(orphan.hasUnsavedEdits == false)
    }

    // MARK: - P2: the wrapping title stays one line

    @Test func aTitleWithoutLineBreaksPassesThroughUntouched() {
        let input = ActionEditModel.titleInput("Call the  landlord ")
        #expect(input.text == "Call the  landlord ")
        #expect(input.submitted == false)
    }

    @Test func returnInTheTitleSubmitsInsteadOfBreakingTheLine() async {
        let (model, editor) = make(fixture(title: "Old title"))
        #expect(editor.setTitle("New title\n"))
        #expect(editor.title == "New title")
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(editor.id)?.title == "New title")
    }

    @Test func pastedLinesJoinIntoOneTitle() {
        let input = ActionEditModel.titleInput("Book flights\r\n  and hotel\n\n")
        #expect(input.text == "Book flights and hotel")
        #expect(input.submitted)
    }

    /// A bare Return changes nothing, so it must not mark the title dirty (no pointless rename).
    @Test func aBareReturnDoesNotDirtyTheTitle() {
        let (_, editor) = make(fixture(title: "Same"))
        #expect(editor.setTitle("Same\n"))
        #expect(editor.hasUnsavedEdits == false)
    }

    /// While the title field has the keyboard, a typing pause must not rename the note.
    @Test func aHeldTitleWaitsForBlurWhileOtherFieldsSave() async {
        let action = fixture(title: "Old title")
        let (model, editor) = make(action)
        editor.setTitleHeld(true)
        editor.setTitle("New ti")
        editor.setWhy("saved meanwhile")
        await editor.waitForPendingSave()

        #expect(model.snapshot.action(action.id)?.title == "Old title")
        #expect(model.snapshot.action(action.id)?.why == "saved meanwhile")
        #expect(editor.title == "New ti")
        #expect(editor.hasUnsavedEdits)

        editor.setTitle("New title")
        editor.setTitleHeld(false)
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(editor.id)?.title == "New title")
        #expect(editor.hasUnsavedEdits == false)
    }

    @Test func flushWritesAHeldTitle() async {
        let (model, editor) = make(fixture(title: "Old title"))
        editor.setTitleHeld(true)
        editor.setTitle("New title")
        await editor.flush()
        #expect(model.snapshot.action(editor.id)?.title == "New title")
        #expect(editor.isTitleHeld == false)
    }

    // MARK: - P8: complete and trash from the detail

    @Test func completeWritesPendingEditsFirst() async {
        let (model, editor) = make(fixture())
        editor.setWhy("typed just before ticking off")
        #expect(await editor.complete())
        let saved = model.snapshot.action(editor.id)
        #expect(saved?.status == .done)
        #expect(saved?.why == "typed just before ticking off")
        #expect(editor.isClosed)
        #expect(editor.hasUnsavedEdits == false)
    }

    @Test func completeFollowsAPendingRename() async {
        let (model, editor) = make(fixture(title: "Old title"))
        editor.setTitle("New title")
        #expect(await editor.complete())
        let expected = model.snapshot.config.layout.actionPath(title: "New title")
        #expect(editor.id == expected)
        #expect(model.snapshot.action(expected)?.status == .done)
    }

    /// I4c — trashing moves the note to `GTD/Trash/`: it leaves the snapshot, and no
    /// `status: trash` is written. Nothing is hard-deleted, so undo brings it back.
    @Test func trashIsAMoveNotAStatusAndNotADeletion() async {
        let (model, editor) = make(fixture())
        let id = editor.id
        #expect(await editor.trash())
        #expect(model.snapshot.action(id) == nil)
        #expect(editor.isClosed)
        await model.undo()
        #expect(model.snapshot.action(id) != nil)
    }

    @Test func undoReopensAClosedAction() async {
        let (model, editor) = make(fixture())
        #expect(await editor.complete())
        await model.undo()
        editor.refresh()
        #expect(editor.isClosed == false)
        #expect(editor.status == .someday)
    }

    /// A refused edit must not be thrown away by ticking the action off.
    @Test func aRefusedEditKeepsTheActionOpen() async {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.actions.append(fixture(title: "Fills the cap", status: .next))
        let (model, editor) = make(fixture(title: "One too many"), snapshot: snapshot)
        editor.setStatus(.next)
        await editor.waitForPendingSave()

        #expect(await editor.complete() == false)
        #expect(editor.lastError is GTDError)
        #expect(model.snapshot.action(editor.id)?.status == .someday)
    }

    // MARK: - A2

    @Test func twoCheckboxesSuggestAProject() {
        let (_, editor) = make(fixture(what: "- [ ] one"))
        #expect(editor.suggestsProject == false)
        editor.setWhat("- [ ] one\n- [ ] two")
        #expect(editor.suggestsProject)
    }
}
