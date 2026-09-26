import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureLists

@MainActor
struct ListsModelTests {

    private func make(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> (AppModel, ListsModel) {
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                      env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
        return (model, ListsModel(model: model))
    }

    // MARK: - Rows and counts

    @Test func rowsMatchRulesListRows() {
        let (_, lists) = make()
        #expect(lists.rows.map(\.list.name) == Rules.listRows(Fixtures.sampleSnapshot).map(\.list.name))
        #expect(lists.rows.contains { $0.list.name == "Read" })
    }

    @Test func totalOpenCountIsOpenItemsAcrossEveryList() {
        let (_, lists) = make()
        #expect(lists.totalOpenCount == Rules.openListItemCount(Fixtures.sampleSnapshot))
        #expect(lists.totalOpenCount > 0)
    }

    /// Proof the test above can actually fail: an empty snapshot has no open items.
    @Test func totalOpenCountIsZeroWithNoLists() {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.lists = []
        snapshot.listItems = []
        let (_, lists) = make(snapshot: snapshot)
        #expect(lists.totalOpenCount == 0)
    }

    @Test func openAndFinishedItemsAreSplitByList() {
        let (_, lists) = make()
        let openRead = lists.openItems(in: "Read")
        let finishedRead = lists.finishedItems(in: "Read")
        #expect(openRead.allSatisfy { !$0.isFinished })
        #expect(finishedRead.allSatisfy { $0.isFinished })
        #expect(!finishedRead.isEmpty, "the sample vault has one finished Read item (L3)")
        #expect(lists.openItems(in: "Watch").allSatisfy { $0.list == "Watch" })
    }

    // MARK: - Adding (L1)

    @Test func addAppendsAnOpenItemToTheList() async {
        let (model, lists) = make()
        let before = lists.openItems(in: "Wish").count
        let ok = await lists.add("  A hammock ", to: "Wish")
        #expect(ok)
        #expect(model.lastError == nil)
        let added = lists.openItems(in: "Wish").first { $0.title == "A hammock" }
        #expect(added != nil, "the trimmed title is the item")
        #expect(added?.created != nil)
        #expect(lists.openItems(in: "Wish").count == before + 1)
        #expect(model.undoLabel == "Added to Wish")
    }

    @Test func addRefusesAnEmptyTitleThroughPerform() async {
        let (model, lists) = make()
        let ok = await lists.add("   ", to: "Wish")
        #expect(ok == false)
        #expect(model.lastError != nil, "the refusal reaches the shell's alert, never swallowed")
    }

    @Test func canAddIsFalseForWhitespaceOnly() {
        #expect(ListsModel.canAdd("") == false)
        #expect(ListsModel.canAdd(" \n") == false)
        #expect(ListsModel.canAdd(" Milk") == true)
    }

    // MARK: - Row commands

    @Test func completeMovesTheItemToDone() async {
        let (model, lists) = make()
        let item = lists.openItems(in: "Watch")[0]
        let ok = await lists.complete(item.id)
        #expect(ok)
        #expect(model.snapshot.listItem(item.id) == nil)
        #expect(model.snapshot.listItems.contains { $0.title == item.title && $0.isFinished })
        #expect(model.lastError == nil)
    }

    @Test func trashRemovesTheItemFromTheSnapshot() async {
        let (model, lists) = make()
        let item = lists.openItems(in: "Wish")[0]
        let ok = await lists.trash(item.id)
        #expect(ok)
        #expect(model.snapshot.listItem(item.id) == nil)
    }

    /// Every refusal reaches `AppModel.lastError` through `perform` — never swallowed.
    @Test func trashingAMissingItemSurfacesNotFound() async {
        let (model, lists) = make()
        let ghost = NoteID(path: "Lists/Read/Never existed.md")
        let ok = await lists.trash(ghost)
        #expect(ok == false)
        guard case .notFound = model.lastError as? GTDError else {
            Issue.record("expected .notFound, got \(String(describing: model.lastError))")
            return
        }
    }

    // MARK: - Make action

    @Test func makeActionModelStartsFromTheListItem() {
        let (_, lists) = make()
        let item = lists.openItems(in: "Read")[0]
        let makeAction = lists.makeActionModel(for: item)
        #expect(makeAction.item?.id == item.id)
        #expect(makeAction.source == .listItem(item))
        #expect(makeAction.draft.title == item.title)
        #expect(makeAction.isFiled == false)
    }
}
