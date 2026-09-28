import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureLists

/// #56 — a list item's held notes reach the crash journal like an action's body.
@MainActor
struct ListItemUnsavedTextTests {
    @Test func heldNotesAreJournaledAndClearedByTheFlush() async throws {
        let snapshot = Fixtures.sampleSnapshot
        let item = try #require(snapshot.listItems.first)
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                     env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot, today: { Fixtures.today })
        let store = InMemoryUnsavedTextStore()
        model.unsavedJournal = UnsavedTextJournal(store: store, delay: .zero)
        let editor = ListItemEditModel(model: model, id: item.id)

        editor.setNotes("typed notes")
        model.unsavedJournal?.writeNow()
        #expect(store.entries.map(\.kind) == [.listItem])
        #expect(store.entries.first?.text == "typed notes")

        await model.flushHeldEdits()
        #expect(store.entries.isEmpty)
        #expect(model.snapshot.listItem(item.id)?.notes == "typed notes")
        _ = editor
    }
}
