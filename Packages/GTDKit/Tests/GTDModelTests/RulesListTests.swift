import Testing
import Foundation
import GTDModel
import GTDFixtures

/// §5a — the queries the Lists UI reads, and the promise that list items stay out of everything
/// else: a list item is not a commitment, so no action query, no count and no review may see one.
struct RulesListTests {

    private func vault() -> VaultSnapshot {
        TestVault.snapshot(
            lists: ["Watch", "read", "Wish", "Archive ideas"].map { GTDList(name: $0) },
            listItems: [
                TestVault.listItem("read", "Sapiens", created: -2),
                TestVault.listItem("read", "Why we sleep", created: -10),
                TestVault.listItem("read", "Thinking Fast and Slow", finished: true, created: -30),
                TestVault.listItem("Watch", "Arrival", created: -5),
            ])
    }

    // MARK: - Order and counts

    @Test func listsAreAlphabeticalIgnoringCase() {
        #expect(Rules.lists(vault()).map(\.name) == ["Archive ideas", "read", "Watch", "Wish"])
    }

    @Test func rowsCarryOpenAndFinishedCounts() {
        let rows = Rules.listRows(vault())
        #expect(rows.map(\.list.name) == ["Archive ideas", "read", "Watch", "Wish"])
        #expect(rows.map(\.openCount) == [0, 2, 1, 0])
        #expect(rows.map(\.finishedCount) == [0, 1, 0, 0])
    }

    /// An empty folder is a list — it just has nothing in it yet (L2).
    @Test func anEmptyListIsStillAList() {
        #expect(Rules.listRows(vault()).contains { $0.list.name == "Wish" && $0.openCount == 0 })
    }

    @Test func theItemsOfAListAreNewestFirstAndFinishedOnesAreSeparate() {
        let open = Rules.listItems(vault(), in: "read")
        #expect(open.map(\.title) == ["Sapiens", "Why we sleep"])
        let done = Rules.listItems(vault(), in: "read", finished: true)
        #expect(done.map(\.title) == ["Thinking Fast and Slow"])
    }

    @Test func aListIsFoundWhateverTheCaseOfTheNameAsked() {
        #expect(Rules.listItems(vault(), in: "READ").count == 2)
    }

    /// E3/L5 — one sidebar row, one number: everything still to read / watch / buy.
    @Test func theSidebarCountsOpenItemsAcrossEveryList() {
        #expect(Rules.openListItemCount(vault()) == 3)
        #expect(Rules.sidebarCounts(vault(), today: TestVault.today).lists == 3)
    }

    // MARK: - Favourites (R-5)

    /// Absent in `GTD/Config.md` ⇒ the first four lists alphabetically, derived and never written.
    @Test func favouritesDefaultToTheFirstFourListsAlphabetically() {
        var snapshot = vault()
        snapshot.lists.append(GTDList(name: "Zzz"))
        #expect(snapshot.config.favouriteLists == nil)
        #expect(Rules.favouriteLists(snapshot).map(\.name)
            == ["Archive ideas", "read", "Watch", "Wish"])
    }

    @Test func aStoredChoiceKeepsTheUsersOrder() {
        var snapshot = vault()
        snapshot.config.favouriteLists = ["Wish", "read"]
        #expect(Rules.favouriteLists(snapshot).map(\.name) == ["Wish", "read"])
    }

    /// A vault edited by hand can name a list that is gone; a ghost row is worse than no row.
    @Test func aFavouriteThatNoLongerExistsIsSkipped() {
        var snapshot = vault()
        snapshot.config.favouriteLists = ["Wish", "Gone", "read"]
        #expect(Rules.favouriteLists(snapshot).map(\.name) == ["Wish", "read"])
    }

    @Test func anEmptyStoredChoiceMeansNoFavourites() {
        var snapshot = vault()
        snapshot.config.favouriteLists = []
        #expect(Rules.favouriteLists(snapshot).isEmpty)
    }

    // MARK: - L6 / L1: list items are invisible everywhere else

    /// Every action query answers the same whether the vault holds list items or not.
    @Test func noActionQuerySeesAListItem() {
        let withoutLists = TestVault.snapshot(
            actions: [TestVault.action("Call the bank", .next, contexts: ["calls"])])
        var withLists = withoutLists
        withLists.lists = vault().lists
        withLists.listItems = vault().listItems

        let today = TestVault.today
        #expect(Rules.nextList(withLists, today: today) == Rules.nextList(withoutLists, today: today))
        #expect(Rules.visibleActions(withLists, today: today).count == 1)
        #expect(Rules.waitingList(withLists, today: today).isEmpty)
        #expect(Rules.chaseItems(withLists, today: today).isEmpty)
        #expect(Rules.countsTowardCap(withLists, today: today) == 1)
        #expect(Rules.archiveCandidates(withLists, today: today).isEmpty)
        #expect(Rules.timeline(withLists, from: TestVault.day(-100), to: TestVault.day(100))
            .isEmpty)
        // …and the sidebar counts them only under `lists`.
        let counts = Rules.sidebarCounts(withLists, today: today)
        #expect(counts.next == 1)
        #expect(counts.someday == 0)
        #expect(counts.inbox == 0)
        #expect(counts.lists == 3)
    }

    /// P4 — a list item can never keep a project off the stalled list: it is not an action.
    @Test func aListItemDoesNotUnstallAProject() {
        var snapshot = vault()
        snapshot.projects = [TestVault.project("Wohnungssuche")]
        #expect(Rules.stalledProjects(snapshot, today: TestVault.today).count == 1)
    }
}
