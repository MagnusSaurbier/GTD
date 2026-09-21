import Testing
import Foundation
import GTDModel
import GTDFixtures
import GTDAppCore
@testable import FeatureSettings

/// Drives `SettingsSession` through `AppModel` + `InMemoryBackend`, the same integration style
/// `AppModelAcceptanceTests` uses — proves the settings edits actually reach the snapshot via
/// `GTDCommand`, not just the pure `ContextsEditing` helpers.
@MainActor
struct SettingsSessionTests {
    private func makeSession(_ snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> SettingsSession {
        let backend = InMemoryBackend(snapshot: snapshot, deviceID: "test")
        let model = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        return SettingsSession(model: model)
    }

    @Test func addContextReachesTheSnapshot() async throws {
        let session = makeSession()
        try await session.addContext("outdoors")
        #expect(session.config.contexts.contains("outdoors"))
    }

    @Test func renameAndRemoveContextGoThroughUpdateConfig() async throws {
        let session = makeSession()
        try await session.renameContext("phone", to: "mobile")
        #expect(session.config.contexts.contains("mobile"))
        #expect(!session.config.contexts.contains("phone"))

        try await session.removeContext("mobile")
        #expect(!session.config.contexts.contains("mobile"))
    }

    @Test func toggleOnTheGoIsReflectedImmediately() async throws {
        let session = makeSession()
        #expect(!session.config.onTheGoContexts.contains("deep-work"))
        try await session.toggleOnTheGo("deep-work")
        #expect(session.config.onTheGoContexts.contains("deep-work"))
    }

    @Test func reorderContextsChangesTheOrder() async throws {
        let session = makeSession()
        let first = session.config.contexts[0]
        try await session.reorderContexts(from: IndexSet(integer: 0), to: 2)
        #expect(session.config.contexts[1] == first)
    }

    @Test func setNextCapUpdatesTheConfig() async throws {
        let session = makeSession()
        try await session.setNextCap(20)
        #expect(session.config.nextCap == 20)
    }

    @Test func setNextCapRejectsZeroOrBelow() async throws {
        let session = makeSession()
        await #expect(throws: GTDError.invalid("Next cap must be at least 1")) {
            try await session.setNextCap(0)
        }
        #expect(session.config.nextCap == GTDConfig.default.nextCap)
    }

    @Test func setRoutineTimeReachesTheRoutine() async throws {
        let session = makeSession()
        let routine = try #require(session.routines.first)
        try await session.setRoutineTime(routine.id, to: DayTime(hour: 6, minute: 30))
        #expect(session.routines.first { $0.id == routine.id }?.time == DayTime(hour: 6, minute: 30))

        try await session.setRoutineTime(routine.id, to: nil)
        #expect(session.routines.first { $0.id == routine.id }?.time == nil)
    }

    @Test func affectedActionCountMatchesTheSnapshot() {
        let session = makeSession()
        #expect(session.affectedActionCount(for: "mac") ==
            ContextsEditing.affectedActionCount(for: "mac", in: Fixtures.sampleSnapshot.actions))
    }

    // MARK: Lists (L2, R-5)

    @Test func createListAddsAnEmptyList() async throws {
        let session = makeSession()
        try await session.createList("Podcasts")
        #expect(session.listRows.contains { $0.list.name == "Podcasts" && $0.openCount == 0 })
    }

    @Test func createListRefusesAnEmptyName() async throws {
        let session = makeSession()
        await #expect(throws: GTDError.invalid("A list name is required")) {
            try await session.createList("   ")
        }
    }

    @Test func createListRefusesTheReservedDoneName() async throws {
        let session = makeSession()
        await #expect(throws: (any Error).self) { try await session.createList("Done") }
    }

    @Test func createListRefusesADuplicateNameCaseInsensitively() async throws {
        let session = makeSession()
        await #expect(throws: GTDError.titleCollision("Read")) {
            try await session.createList("read")
        }
    }

    @Test func renameListCarriesItsItemsAndUpdatesTheRows() async throws {
        let session = makeSession()
        try await session.renameList("Watch", to: "Watchlist")
        #expect(!session.listRows.contains { $0.list.name == "Watch" })
        let renamed = try #require(session.listRows.first { $0.list.name == "Watchlist" })
        #expect(renamed.openCount == 2)
    }

    @Test func renameListRefusesACaseOnlyRename() async throws {
        let session = makeSession()
        await #expect(throws: GTDError.invalid("Renaming a list only by capitalisation is not supported")) {
            try await session.renameList("Read", to: "read")
        }
    }

    @Test func renameListRefusesAnUnknownList() async throws {
        let session = makeSession()
        await #expect(throws: (any Error).self) {
            try await session.renameList("Podcasts", to: "Newsletters")
        }
    }

    @Test func removeListMovesItsItemsAwayAndFreesTheName() async throws {
        let session = makeSession()
        try await session.removeList("Wish")
        #expect(!session.listRows.contains { $0.list.name == "Wish" })
        // The name is free again — this would throw `.invalid` if the folder still existed.
        try await session.createList("Wish")
        #expect(session.listRows.contains { $0.list.name == "Wish" })
    }

    @Test func removeListDropsItFromExplicitFavourites() async throws {
        let session = makeSession()
        try await session.createList("Aaa")
        try await session.createList("Bbb")
        // Five lists now (Aaa, Bbb, Read, Watch, Wish); the derived default (first four
        // alphabetically) is Aaa/Bbb/Read/Watch, so toggling Wish *adds* it explicitly.
        try await session.toggleFavourite("Wish")
        #expect(session.favouriteListNames.contains("Wish"))
        try await session.removeList("Wish")
        #expect(!session.favouriteListNames.contains("Wish"))
    }

    @Test func renameListRenamesItsFavourite() async throws {
        let session = makeSession()
        try await session.toggleFavourite("Read") // explicit choice: [Watch, Wish]
        try await session.renameList("Wish", to: "Gifts")
        #expect(session.favouriteListNames == ["Watch", "Gifts"])
        #expect(session.config.favouriteLists == ["Watch", "Gifts"])
    }

    /// A folder removed or renamed outside the app (Finder, Obsidian) leaves a stale name in
    /// `favouriteLists`. It is not shown, and the next favourites edit drops it from the file
    /// instead of being refused as an unknown list.
    @Test func aFavouriteWhoseFolderIsGoneIsDroppedAndDoesNotBlockEdits() async throws {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.config.favouriteLists = ["Watch", "Gone", "Wish"]
        let session = makeSession(snapshot)
        #expect(session.favouriteListNames == ["Watch", "Wish"])
        #expect(!session.listsAvailableToFavourite.contains("Gone"))

        try await session.reorderFavourites(from: IndexSet(integer: 1), to: 0)
        #expect(session.config.favouriteLists == ["Wish", "Watch"])

        try await session.toggleFavourite("Read")
        #expect(session.config.favouriteLists == ["Wish", "Watch", "Read"])
    }

    @Test func itemCountMatchesOpenPlusFinished() {
        let session = makeSession()
        // Fixtures: Read has 3 open + 1 finished (`GTDFixtures.SampleSnapshot`).
        #expect(session.itemCount(inList: "Read") == 4)
        #expect(session.itemCount(inList: "Wish") == 1)
        #expect(session.itemCount(inList: "Nonexistent") == 0)
    }

    // MARK: Favourites (I4b, R-5)

    @Test func favouriteListNamesDefaultsToTheFirstFourAlphabeticallyWithoutWriting() async throws {
        let session = makeSession()
        try await session.createList("Articles")
        try await session.createList("Podcasts")
        // Five lists now (Articles, Podcasts, Read, Watch, Wish); still unset.
        #expect(session.config.favouriteLists == nil)
        #expect(session.favouriteListNames == ["Articles", "Podcasts", "Read", "Watch"])
        // Reading it again still has not written anything (no lying defaults / R-5).
        #expect(session.config.favouriteLists == nil)
    }

    @Test func toggleFavouriteStartsFromTheShownDefaultThenWrites() async throws {
        let session = makeSession()
        #expect(session.config.favouriteLists == nil)
        try await session.toggleFavourite("Wish")
        // Wish was already in the (3-list) derived default, so toggling it *removes* it.
        #expect(session.config.favouriteLists != nil)
        #expect(!session.favouriteListNames.contains("Wish"))
        #expect(session.favouriteListNames.contains("Read"))
    }

    @Test func toggleFavouriteAddsANewListOnTopOfTheDefault() async throws {
        let session = makeSession()
        try await session.createList("Aaa")
        try await session.createList("Bbb")
        // Five lists now; the derived default (first four alphabetically) is Aaa/Bbb/Read/Watch
        // — Wish falls just outside it.
        #expect(session.favouriteListNames == ["Aaa", "Bbb", "Read", "Watch"])
        try await session.toggleFavourite("Wish")
        #expect(session.favouriteListNames == ["Aaa", "Bbb", "Read", "Watch", "Wish"])
    }

    @Test func toggleFavouriteRefusesPastTheStorageLimit() async throws {
        let session = makeSession()
        for index in 1...6 { try await session.createList("Extra\(index)") }
        // Fill to the storage limit with whatever is not already a favourite — robust to
        // exactly which lists the derived default happened to start with.
        while session.favouriteListNames.count < ListsEditing.storageLimit {
            guard let name = session.listsAvailableToFavourite.first else { break }
            try await session.toggleFavourite(name)
        }
        #expect(session.favouriteListNames.count == ListsEditing.storageLimit)
        let overflow = try #require(session.listsAvailableToFavourite.first)
        await #expect(throws: ListsEditing.FavouriteError.limitReached(ListsEditing.storageLimit)) {
            try await session.toggleFavourite(overflow)
        }
        #expect(session.favouriteListNames.count == ListsEditing.storageLimit)
    }

    @Test func reorderFavouritesChangesTheStoredOrder() async throws {
        let session = makeSession()
        try await session.toggleFavourite("Read") // seed an explicit choice: [Watch, Wish]
        #expect(session.favouriteListNames == ["Watch", "Wish"])
        try await session.reorderFavourites(from: IndexSet(integer: 1), to: 0)
        #expect(session.favouriteListNames == ["Wish", "Watch"])
    }

    @Test func listsAvailableToFavouriteExcludesCurrentFavourites() {
        let session = makeSession()
        #expect(!session.listsAvailableToFavourite.contains("Read"))
    }
}
