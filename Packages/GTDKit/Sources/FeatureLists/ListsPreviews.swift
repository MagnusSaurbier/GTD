#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import GTDFixtures

/// STYLEGUIDE §9: light, dark, AX1, and every component state.

#Preview("Lists home") {
    NavigationStack { ListsHomeView() }
        .environment(previewModel())
}

#Preview("Lists home · dark") {
    NavigationStack { ListsHomeView() }
        .environment(previewModel())
        .preferredColorScheme(.dark)
}

#Preview("Lists home · AX1") {
    NavigationStack { ListsHomeView() }
        .environment(previewModel())
        .dynamicTypeSize(.accessibility1)
}

#Preview("Lists home · empty") {
    NavigationStack { ListsHomeView() }
        .environment(previewModel(snapshot: Fixtures.sampleSnapshot.withNoLists()))
}

#Preview("List items · Read") {
    NavigationStack { ListItemsView(list: "Read") }
        .environment(previewModel())
}

#Preview("List items · empty") {
    NavigationStack { ListItemsView(list: "Wish") }
        .environment(previewModel(snapshot: Fixtures.sampleSnapshot.withNoLists()))
}

#Preview("Item editor") {
    NavigationStack {
        ListItemEditorView(item: Fixtures.sampleSnapshot.listItems[0].id)
    }
    .environment(previewModel())
}

#Preview("Make action") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MakeActionSheet(model: previewModel(), item: Fixtures.sampleSnapshot.listItems[0])
        }
}

#Preview("Lists sections (Mac)") {
    ListsSectionsView(onOpen: { _ in })
        .environment(previewModel())
        .frame(width: 420, height: 600)
}

@MainActor
private func previewModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
    AppModel(
        backend: InMemoryBackend(snapshot: snapshot),
        snapshot: snapshot,
        today: { Fixtures.today })
}

private extension VaultSnapshot {
    /// The "no lists yet" empty state (§3.9).
    func withNoLists() -> VaultSnapshot {
        var copy = self
        copy.lists = []
        copy.listItems = []
        return copy
    }
}
#endif
