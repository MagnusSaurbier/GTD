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

    /// The user is typing in the body while the vault changes a *different* field (sync,
    /// another device, a command from another view). Neither side may lose its value.
    @Test func aSnapshotArrivingMidEditClobbersNeitherSide() async throws {
        let action = fixture()
        let (model, editor) = make(action)

        // 1. The user types — not yet saved.
        editor.setWhy("my new why")

        // 2. Something else rewrites a *different* field of the same note.
        var remote = try #require(model.snapshot.action(action.id))
        remote.timeEstimate = 45
        try await model.send(.updateAction(remote))
        editor.refresh()

        // The editor shows the user's text *and* the remote change.
        #expect(editor.why == "my new why")
        #expect(editor.timeBucket == TimeBucket(minutes: 45))

        // 3. The debounced save lands: it writes only the edited field.
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.why == "my new why")
        #expect(saved.timeEstimate == 45)               // NOT reverted to the stale draft
        #expect(editor.hasUnsavedEdits == false)
    }

    /// An untouched field keeps following the vault; a touched one does not jump back. The body
    /// is **one** field (2026-09-24): while the person is typing in it, a remote change to any
    /// part of it — `Why?` or `What?` alike — waits until the edit is written.
    @Test func refreshAdoptsRemoteValuesOnlyForUntouchedFields() async throws {
        let action = fixture()
        let (model, editor) = make(action)
        editor.setWhy("local why")

        var remote = try #require(model.snapshot.action(action.id))
        remote.what = "remote what"
        remote.timeEstimate = 45
        try await model.send(.updateAction(remote))
        editor.refresh()

        #expect(editor.why == "local why")
        #expect(editor.what == "old what")
        #expect(editor.timeBucket == TimeBucket(minutes: 45))
    }

    // MARK: - A1: the body is one document with its two headings

    /// The editor shows the note's whole body — a section the app does not know about included —
    /// and writes back exactly what was typed.
    @Test func theWholeBodyIsEditedAsOneDocument() async throws {
        var action = fixture()
        action.body = "# Why?\nold why\n\n# Notes\nKeep this.\n\n# What?\nold what"
        let (model, editor) = make(action)
        #expect(editor.body == action.body)

        editor.setBody(action.body + "\n- [ ] one more")
        await editor.flush()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.body == "# Why?\nold why\n\n# Notes\nKeep this.\n\n# What?\nold what\n- [ ] one more")
        #expect(saved.what == "old what\n- [ ] one more")
    }

    /// A note without the action headings shows them (its text under `# What?`, where the codec
    /// has always read it) — and nothing is written until the person edits.
    @Test func missingHeadingsAreShownAndWrittenWithTheFirstEdit() async throws {
        var action = fixture()
        action.body = "Just a line somebody typed in Obsidian."
        let (model, editor) = make(action)
        #expect(editor.body == "# Why?\n\n# What?\nJust a line somebody typed in Obsidian.")
        #expect(editor.hasUnsavedEdits == false)
        await editor.flush()
        #expect(model.snapshot.action(editor.id)?.body == "Just a line somebody typed in Obsidian.")

        editor.setBody("# Why?\nBecause.\n\n# What?\nJust a line somebody typed in Obsidian.")
        await editor.flush()
        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.body == "# Why?\nBecause.\n\n# What?\nJust a line somebody typed in Obsidian.")
        #expect(saved.why == "Because.")
    }

    /// The editor echoing the displayed text back (SwiftUI does that on focus) is not an edit.
    @Test func echoingTheDisplayedBodyIsNotAnEdit() async {
        var action = fixture()
        action.body = "Just a line."
        let (_, editor) = make(action)
        editor.setBody(editor.body)
        #expect(editor.hasUnsavedEdits == false)
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

    /// #86 — the detail's Defer chip defers: the item waits with that follow-up date and no
    /// who, the chip shows the date, and clearing it brings the item back to Next.
    @Test func theDeferChipMakesADeferralAndClearingItUndefers() async throws {
        var action = fixture(status: .next)
        action.timeEstimate = 30
        let (model, editor) = make(action)
        editor.setDeferDate(Fixtures.day(5))
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.status == .waiting)
        #expect(saved.waiting == WaitingInfo(followUp: Fixtures.day(5)))
        #expect(editor.deferDate == Fixtures.day(5))

        editor.setDeferDate(nil)
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(editor.id)?.status == .next)
        #expect(editor.deferDate == nil)
        #expect(editor.lastError == nil)
    }

    /// #86 — on a Someday item the Defer chip is its own defer date: it stays Someday.
    @Test func theDeferChipOnASomedayItemKeepsItSomeday() async throws {
        let (model, editor) = make(fixture(status: .someday))
        editor.setDeferDate(Fixtures.day(5))
        await editor.waitForPendingSave()
        let saved = try #require(model.snapshot.action(editor.id))
        #expect(saved.status == .someday)
        #expect(saved.deferDate == Fixtures.day(5))
        #expect(editor.deferDate == Fixtures.day(5))
        editor.setDeferDate(nil)
        await editor.waitForPendingSave()
        #expect(model.snapshot.action(editor.id)?.deferDate == nil)
        #expect(model.snapshot.action(editor.id)?.status == .someday)
    }

    /// The user's 2026-09-24 report: context and time chips on an imported waiting item (no
    /// follow-up date) showed "Still missing: Follow-up" and the edit was gone on leaving.
    @Test func chipsOnAWaitingNoteWithoutAFollowUpDateAreSaved() async throws {
        var action = fixture(title: "Coaching", status: .waiting)
        action.waitingFor = "Coach"
        let (model, editor) = make(action)

        editor.setContexts(["mac", "phone"])
        editor.setTimeEstimate(10)
        await editor.waitForPendingSave()

        let saved = try #require(model.snapshot.action(editor.id))
        #expect(editor.lastError == nil)
        #expect(editor.hasUnsavedEdits == false)
        #expect(saved.contexts == ["mac", "phone"])
        #expect(saved.timeEstimate == 10)
        #expect(saved.waitingFor == "Coach")
        #expect(saved.followUpDate == nil)
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

/// The tests type into one section of the single body field, as a person would.
@MainActor
private extension ActionEditModel {
    func setWhy(_ value: String) {
        setBody(NoteBody.setText("Why?", value, in: body, canonicalOrder: NoteBody.actionSections))
    }
    func setWhat(_ value: String) {
        setBody(NoteBody.setText("What?", value, in: body, canonicalOrder: NoteBody.actionSections))
    }
    var why: String { NoteBody.text(of: "Why?", in: body) ?? "" }
    var what: String { NoteBody.text(of: "What?", in: body) ?? "" }
}
