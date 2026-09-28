import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureOverview

/// #56 — typed-but-held text reaches the crash journal, leaves it once saved, and comes back
/// through `AppModel.restoreUnsaved` after a "crash" (a new journal on the same store).
@MainActor
struct UnsavedTextJournalTests {

    private func make() throws -> (AppModel, Action, InMemoryUnsavedTextStore) {
        let snapshot = Fixtures.sampleSnapshot
        let action = try #require(snapshot.actions.first)
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                     env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
        let store = InMemoryUnsavedTextStore()
        model.unsavedJournal = UnsavedTextJournal(store: store, delay: .zero)
        return (model, action, store)
    }

    @Test func heldBodyTextIsJournaledAndClearedByTheFlush() async throws {
        let (model, action, store) = try make()
        let editor = ActionEditModel(model: model, id: action.id)

        editor.setBody("# Why?\nwritten before the crash")
        model.unsavedJournal?.writeNow()
        let journaled = try #require(store.entries.first)
        #expect(journaled.kind == .action)
        #expect(journaled.path == action.id.path)
        #expect(journaled.text == "# Why?\nwritten before the crash")
        #expect(journaled.title == nil, "an untouched title is not journaled")

        await model.flushHeldEdits()
        #expect(store.entries.isEmpty, "saved text leaves the journal")
        _ = editor
    }

    /// A chip is saved at once, so it never counts as unsaved text.
    @Test func clicksAreNotJournaled() async throws {
        let (model, action, store) = try make()
        let editor = ActionEditModel(model: model, id: action.id)
        editor.setContexts(["phone"])
        await editor.waitForPendingSave()
        model.unsavedJournal?.writeNow()
        #expect(store.entries.isEmpty)
    }

    @Test func aRestoreAfterACrashWritesTheTextIntoTheNote() async throws {
        let (model, action, store) = try make()
        let editor = ActionEditModel(model: model, id: action.id)
        editor.setBody("lost?")
        model.unsavedJournal?.writeNow()

        // The next launch: a new journal reads the same store; the editor is gone.
        let relaunched = UnsavedTextJournal(store: store, delay: .zero)
        model.unsavedJournal = relaunched
        let entry = try #require(relaunched.recovered.first)

        #expect(await model.restoreUnsaved(entry))
        #expect(model.snapshot.action(action.id)?.body == "lost?")
        #expect(relaunched.recovered.isEmpty)
        #expect(store.entries.allSatisfy { $0 != entry })
        _ = editor
    }

    @Test func discardLetsItGo() async throws {
        let (model, action, store) = try make()
        model.unsavedJournal = UnsavedTextJournal(store: InMemoryUnsavedTextStore([
            UnsavedText(kind: .action, path: action.id.path, title: nil, text: "x", savedAt: Date())
        ]))
        let entry = try #require(model.unsavedJournal?.recovered.first)
        model.discardUnsaved(entry)
        #expect(model.unsavedJournal?.recovered.isEmpty == true)
        #expect(model.snapshot.action(action.id)?.body == action.body)
        _ = store
    }
}
