import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureLists

/// The dangerous part of `ListItemEditModel`: debounced autosave must not lose an edit, must not
/// clobber a snapshot that arrives mid-edit, and must follow the `NoteID` a title rename creates.
/// Mirrors `FeatureOverviewTests/ActionEditModelTests` on the smaller `ListItem` shape.
@MainActor
struct ListItemEditModelTests {

    private static let instantSleep: ListItemEditModel.Sleep = { _ in
        try Task.checkCancellation()
    }

    private func make(
        list: String = "Read", title: String = "Draft item", notes: String = "old notes",
        snapshot base: VaultSnapshot = Fixtures.sampleSnapshot
    ) -> (AppModel, ListItemEditModel, NoteID) {
        var snapshot = base
        let id = snapshot.config.layout.listItemPath(list: list, title: title)
        let item = ListItem(id: id, list: list, title: title, notes: notes)
        snapshot.listItems.append(item)
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                      env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
        let editor = ListItemEditModel(
            model: model, id: id, debounce: .milliseconds(1), sleep: Self.instantSleep)
        return (model, editor, id)
    }

    // MARK: - Debounce / autosave

    @Test func typingCoalescesIntoOneSave() async {
        let (model, editor, id) = make()
        editor.setNotes("a")
        editor.setNotes("ab")
        editor.setNotes("abc")
        #expect(editor.hasUnsavedEdits)

        await editor.waitForPendingSave()

        #expect(model.snapshot.listItem(id)?.notes == "abc")
        #expect(editor.hasUnsavedEdits == false)
        #expect(editor.lastError == nil)
    }

    @Test func flushWritesImmediately() async {
        let (model, editor, id) = make()
        editor.setNotes("flushed")
        await editor.flush()
        #expect(model.snapshot.listItem(id)?.notes == "flushed")
    }

    /// The dirty field keeps the user's text across a snapshot that arrives mid-edit, and the
    /// debounced save still lands afterwards — the same overlay rule
    /// `ActionEditModel.refreshAdoptsRemoteValuesOnlyForUntouchedFields` proves on `Action`.
    @Test func aSnapshotArrivingMidEditDoesNotClobberTheDirtyField() async throws {
        let (model, editor, id) = make(title: "Stable title")
        editor.setNotes("local notes")

        // A snapshot republishes (e.g. the vault store's own scan arriving) with nothing new.
        let remote = try #require(model.snapshot.listItem(id))
        try await model.send(.updateListItem(id, title: remote.title, notes: remote.notes))
        editor.refresh()

        #expect(editor.notes == "local notes")

        await editor.waitForPendingSave()
        #expect(model.snapshot.listItem(editor.id)?.notes == "local notes")
    }

    /// An edit made while the save is in flight survives it: it stays dirty and is written next.
    @Test func anEditDuringAnInFlightSaveIsNotDropped() async {
        let (model, editor, id) = make()
        editor.setNotes("first")
        let save = Task { await editor.waitForPendingSave() }
        await Task.yield()
        editor.setNotes("second")
        await save.value
        await editor.waitForPendingSave()

        #expect(editor.notes == "second")
        #expect(model.snapshot.listItem(id)?.notes == "second")
        #expect(editor.hasUnsavedEdits == false)
    }

    // MARK: - Rename following

    @Test func titleChangeFollowsTheRename() async {
        let (model, editor, id) = make(title: "Old title")
        _ = editor.setTitle("New title")
        await editor.waitForPendingSave()

        #expect(editor.id != id)
        #expect(model.snapshot.listItem(id) == nil)
        #expect(model.snapshot.listItem(editor.id)?.title == "New title")
        #expect(editor.isMissing == false)
    }

    /// Proof the rename-following test can fail: an unchanged title never moves the file.
    @Test func unchangedTitleKeepsTheSameID() async {
        let (_, editor, id) = make(title: "Same title")
        editor.setNotes("touch something else")
        await editor.waitForPendingSave()
        #expect(editor.id == id)
    }

    @Test func titleCollisionIsSurfacedNeverSwallowed() async {
        let (_, editor, _) = make(list: "Read", title: "Draft item")
        // Create a second item that will collide once the first is renamed to match it.
        _ = editor.setTitle("Thinking Fast and Slow")   // already exists in the sample vault
        await editor.waitForPendingSave()

        guard case .titleCollision = editor.lastError as? GTDError else {
            Issue.record("expected .titleCollision, got \(String(describing: editor.lastError))")
            return
        }
        #expect(editor.hasUnsavedEdits, "the rejected edit is kept, not thrown away")
    }

    // MARK: - Closing

    @Test func completeMovesTheItemToDone() async {
        let (model, editor, id) = make()
        let ok = await editor.complete()
        #expect(ok)
        #expect(model.snapshot.listItem(id) == nil)
    }

    @Test func trashRemovesTheItem() async {
        let (model, editor, id) = make()
        let ok = await editor.trash()
        #expect(ok)
        #expect(model.snapshot.listItem(id) == nil)
    }

    @Test func missingItemIsReported() {
        let snapshot = Fixtures.sampleSnapshot
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                      env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
        let ghost = NoteID(path: "Lists/Read/Never existed.md")
        let editor = ListItemEditModel(
            model: model, id: ghost, debounce: .milliseconds(1), sleep: Self.instantSleep)
        #expect(editor.isMissing)
        #expect(editor.draft == nil)
    }
}
