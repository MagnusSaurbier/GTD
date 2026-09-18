import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureSettings

/// Pure context-list editing (A4) and the "affected actions" impact count used before a removal
/// is confirmed.
struct ContextsEditingTests {
    private var config: GTDConfig { .default }

    @Test func addingAppendsATrimmedName() {
        let next = ContextsEditing.adding("  outdoors  ", to: config)
        #expect(next.contexts.last == "outdoors")
    }

    @Test func addingIgnoresEmptyAndDuplicateNames() {
        #expect(ContextsEditing.adding("   ", to: config) == config)
        #expect(ContextsEditing.adding("mac", to: config) == config)
    }

    @Test func renamingUpdatesBothListsInPlace() {
        var withOnTheGo = config
        withOnTheGo.onTheGoContexts = ["phone"]
        let next = ContextsEditing.renaming("phone", to: "mobile", in: withOnTheGo)
        #expect(next.contexts.firstIndex(of: "mobile") == withOnTheGo.contexts.firstIndex(of: "phone"))
        #expect(!next.contexts.contains("phone"))
        #expect(next.onTheGoContexts == ["mobile"])
    }

    @Test func renamingToAnExistingNameIsANoOp() {
        #expect(ContextsEditing.renaming("mac", to: "phone", in: config) == config)
    }

    @Test func renamingAnUnknownNameIsANoOp() {
        #expect(ContextsEditing.renaming("nope", to: "new", in: config) == config)
    }

    @Test func removingDropsFromBothLists() {
        let next = ContextsEditing.removing("phone", from: config)
        #expect(!next.contexts.contains("phone"))
        #expect(!next.onTheGoContexts.contains("phone"))
        // Untouched otherwise.
        #expect(next.contexts.count == config.contexts.count - 1)
    }

    @Test func togglingOnTheGoAddsAndRemoves() {
        #expect(!config.onTheGoContexts.contains("deep-work"))
        let added = ContextsEditing.togglingOnTheGo("deep-work", in: config)
        #expect(added.onTheGoContexts.contains("deep-work"))
        let removed = ContextsEditing.togglingOnTheGo("deep-work", in: added)
        #expect(removed == config)
    }

    @Test func togglingOnTheGoIgnoresAContextNotInTheMainList() {
        #expect(ContextsEditing.togglingOnTheGo("nope", in: config) == config)
    }

    @Test func reorderingSwapsDownOneStep() {
        // config.contexts == ["mac", "phone", "home", "campus", ...]
        let next = ContextsEditing.reordering(config, from: IndexSet(integer: 0), to: 2)
        #expect(next.contexts[0] == "phone")
        #expect(next.contexts[1] == "mac")
        #expect(Set(next.contexts) == Set(config.contexts))
    }

    @Test func reorderingSwapsUpOneStep() {
        let next = ContextsEditing.reordering(config, from: IndexSet(integer: 1), to: 0)
        #expect(next.contexts[0] == "phone")
        #expect(next.contexts[1] == "mac")
    }

    @Test func affectedActionCountCountsActionsUsingTheContext() {
        let actions = [
            Fixtures.sampleSnapshot.actions.first { $0.contexts.contains("mac") }!,
        ]
        #expect(ContextsEditing.affectedActionCount(for: "mac", in: Fixtures.sampleSnapshot.actions) > 0)
        #expect(ContextsEditing.affectedActionCount(for: "mac", in: actions) == 1)
        #expect(ContextsEditing.affectedActionCount(for: "some-unused-context", in: Fixtures.sampleSnapshot.actions) == 0)
    }
}
