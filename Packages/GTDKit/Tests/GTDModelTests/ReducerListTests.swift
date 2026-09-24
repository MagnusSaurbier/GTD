import Testing
import Foundation
import GTDModel
import GTDFixtures

/// §5a — the Lists domain: the folder *is* the list, an item is a note, `Done/` is the log.
/// One test per happy path and one per refusal, plus what each command means for undo.
struct ReducerListTests {
    private let env = TestVault.env()

    private func vault(
        lists: [String] = ["Read", "Watch"],
        items: [ListItem] = [],
        actions: [Action] = [],
        inbox: [InboxItem] = [],
        config: GTDConfig = .default
    ) -> VaultSnapshot {
        TestVault.snapshot(
            inbox: inbox,
            actions: actions,
            lists: lists.map { GTDList(name: $0) },
            listItems: items,
            config: config)
    }

    // MARK: - createList (L2)

    @Test func creatingAListCreatesItsFolderAndNothingElse() throws {
        let result = try Reducer.reduce(vault(), .createList(name: "Wish"), env: env)
        #expect(result.snapshot.list(named: "Wish") == GTDList(name: "Wish"))
        // A list is a folder; there is no list note to write.
        #expect(result.extraOps == [.createFolder(path: "Lists/Wish")])
        #expect(result.snapshot.listItems.isEmpty)
    }

    @Test func aListNameIsSanitisedLikeAnyOtherFileName() throws {
        let result = try Reducer.reduce(vault(), .createList(name: "  Wish / Gifts  "), env: env)
        #expect(result.snapshot.lists.map(\.name).contains("Wish Gifts"))
    }

    @Test func anEmptyListNameIsRefused() {
        #expect(TestVault.error(vault(), .createList(name: "   "))
            == .invalid("A list name is required"))
    }

    /// L3/D38 — `Done/` is every list's finished log, so no list may be called that.
    @Test(arguments: ["Done", "done", "DONE"])
    func theDoneFolderNameIsReserved(name: String) {
        #expect(TestVault.error(vault(), .createList(name: name))
            == .invalid("\"Done\" is reserved for finished items and cannot be a list"))
    }

    /// macOS and iOS file systems are case-insensitive: `Read` and `read` cannot both exist.
    @Test(arguments: ["Read", "read", "rEaD"])
    func aDuplicateListNameIsRefusedWhateverItsCase(name: String) {
        #expect(TestVault.error(vault(), .createList(name: name)) == .titleCollision("Read"))
    }

    // MARK: - renameList (L2, R-5)

    @Test func renamingAListMovesTheFolderAndCarriesItsItems() throws {
        let open = TestVault.listItem("Read", "Sapiens")
        let finished = TestVault.listItem("Read", "Why we sleep", finished: true)
        let result = try Reducer.reduce(
            vault(items: [open, finished]), .renameList(from: "Read", to: "Reading"), env: env)

        #expect(result.snapshot.list(named: "Read") == nil)
        #expect(result.snapshot.list(named: "Reading") != nil)
        #expect(result.extraOps == [.moveFolder(from: "Lists/Read", to: "Lists/Reading")])
        #expect(result.snapshot.listItems.allSatisfy { $0.list == "Reading" })
        #expect(result.snapshot.listItem(NoteID(path: "Lists/Reading/Sapiens.md")) != nil)
        // The `Done/` log travels with the folder like everything else (L3).
        #expect(result.snapshot.listItem(
            NoteID(path: "Lists/Reading/Done/Why we sleep.md"))?.isFinished == true)
        // ARCHITECTURE §4 — a rename is reported, so an open item editor follows the note.
        #expect(result.renames.resolve(open.id) == NoteID(path: "Lists/Reading/Sapiens.md"))
        #expect(result.renames.resolve(finished.id)
            == NoteID(path: "Lists/Reading/Done/Why we sleep.md"))
    }

    @Test func renamingAnUnknownListIsRefused() {
        #expect(TestVault.error(vault(), .renameList(from: "Wish", to: "Gifts"))
            == .invalid("Unknown list: Wish"))
    }

    @Test func renamingAListOntoAnExistingOneIsRefused() {
        #expect(TestVault.error(vault(), .renameList(from: "Read", to: "Watch"))
            == .titleCollision("Watch"))
    }

    /// A case-only rename would ask a case-insensitive file system to move a folder onto itself.
    @Test func renamingAListOnlyByCapitalisationIsRefused() {
        #expect(TestVault.error(vault(), .renameList(from: "Read", to: "read"))
            == .invalid("Renaming a list only by capitalisation is not supported"))
    }

    @Test func renamingAListToTheReservedNameIsRefused() {
        #expect(TestVault.error(vault(), .renameList(from: "Read", to: "Done"))
            == .invalid("\"Done\" is reserved for finished items and cannot be a list"))
    }

    @Test func renamingAListToItsOwnNameChangesNothing() throws {
        let start = vault()
        let result = try Reducer.reduce(start, .renameList(from: "Read", to: "Read"), env: env)
        #expect(result.snapshot == start)
        #expect(result.extraOps.isEmpty)
    }

    // MARK: - removeList (L2, R-5, I4c)

    @Test func removingAListMovesTheWholeFolderIntoTheTrash() throws {
        let item = TestVault.listItem("Read", "Sapiens")
        var config = GTDConfig.default
        config.favouriteLists = ["Read", "Watch"]
        let result = try Reducer.reduce(
            vault(items: [item], config: config), .removeList(name: "Read"), env: env)

        #expect(result.snapshot.list(named: "Read") == nil)
        #expect(result.snapshot.listItems.isEmpty)      // the items went with it
        #expect(result.extraOps == [.moveFolder(from: "Lists/Read", to: "GTD/Trash/Read")])
        // A removed list cannot stay a favourite (it would be a ghost in the navbar).
        #expect(result.snapshot.config.favouriteLists == ["Watch"])
    }

    // MARK: - renameList and favourites (R-5)

    @Test func renamingAFavouriteListRenamesTheFavouriteInPlace() throws {
        var config = GTDConfig.default
        config.favouriteLists = ["Watch", "Read"]
        let result = try Reducer.reduce(
            vault(config: config), .renameList(from: "read", to: "Books"), env: env)
        // Same slot, new name — the navbar keeps the list where the user put it.
        #expect(result.snapshot.config.favouriteLists == ["Watch", "Books"])
    }

    @Test func renamingAListLeavesAnUnchosenFavouritesSettingUnset() throws {
        let result = try Reducer.reduce(vault(), .renameList(from: "Read", to: "Books"), env: env)
        #expect(result.snapshot.config.favouriteLists == nil)
    }

    // MARK: - pruneFavouriteLists (R-5)

    @Test func pruningDropsFavouritesWhoseFolderIsGoneAndKeepsTheOrder() throws {
        var config = GTDConfig.default
        config.favouriteLists = ["Watch", "Gone", "read"]
        let result = try Reducer.reduce(vault(config: config), .pruneFavouriteLists, env: env)
        #expect(result.snapshot.config.favouriteLists == ["Watch", "read"])
        #expect(result.extraOps.isEmpty)
    }

    @Test func pruningChangesNothingWhenEveryFavouriteExists() throws {
        var config = GTDConfig.default
        config.favouriteLists = ["Watch", "Read"]
        let start = vault(config: config)
        #expect(try Reducer.reduce(start, .pruneFavouriteLists, env: env).snapshot == start)
    }

    @Test func pruningLeavesAnUnchosenSettingUnset() throws {
        let start = vault()
        #expect(try Reducer.reduce(start, .pruneFavouriteLists, env: env).snapshot == start)
    }

    /// No list at all is far likelier an unsynced `Lists/` than every list gone — keep the choice.
    @Test func pruningKeepsEverythingWhenTheVaultShowsNoListAtAll() throws {
        var config = GTDConfig.default
        config.favouriteLists = ["Read", "Watch"]
        let start = vault(lists: [], config: config)
        #expect(try Reducer.reduce(start, .pruneFavouriteLists, env: env).snapshot == start)
    }

    @Test func pruningIsNotUndoable() {
        #expect(!Rules.isUndoable(.pruneFavouriteLists))
    }

    @Test func removingAnUnknownListIsRefused() {
        #expect(TestVault.error(vault(), .removeList(name: "Wish"))
            == .invalid("Unknown list: Wish"))
    }

    // MARK: - setFavouriteLists (I4b, R-5)

    @Test func favouritesAreStoredInTheUsersOrderAndDeduped() throws {
        let result = try Reducer.reduce(
            vault(), .setFavouriteLists(["Watch", "read", "Watch"]), env: env)
        // Stored the way the folders spell it, so the config and the vault agree.
        #expect(result.snapshot.config.favouriteLists == ["Watch", "Read"])
    }

    @Test func favouritesNamingAListThatDoesNotExistAreRefused() {
        #expect(TestVault.error(vault(), .setFavouriteLists(["Read", "Wish"]))
            == .invalid("Unknown list: Wish"))
    }

    @Test func favouritesCanBeClearedToTheEmptyChoice() throws {
        let result = try Reducer.reduce(vault(), .setFavouriteLists([]), env: env)
        // `[]` is a *choice* ("show none"), and different from `nil` ("never chosen").
        #expect(result.snapshot.config.favouriteLists == [])
    }

    // MARK: - updateListItem

    @Test func editingTheNotesOfAnItemLeavesItsFileWhereItIs() throws {
        let item = TestVault.listItem("Read", "Sapiens")
        let result = try Reducer.reduce(
            vault(items: [item]),
            .updateListItem(item.id, title: "Sapiens", notes: "Marie's copy"),
            env: env)
        #expect(result.snapshot.listItem(item.id)?.notes == "Marie's copy")
        #expect(result.extraOps.isEmpty)
        #expect(result.renames.isEmpty)
    }

    @Test func changingTheTitleRenamesTheFile() throws {
        let item = TestVault.listItem("Read", "Sapiens")
        let result = try Reducer.reduce(
            vault(items: [item]),
            .updateListItem(item.id, title: "Sapiens — Harari", notes: ""),
            env: env)

        let moved = NoteID(path: "Lists/Read/Sapiens — Harari.md")
        #expect(result.snapshot.listItem(moved)?.title == "Sapiens — Harari")
        #expect(result.snapshot.listItem(item.id) == nil)
        #expect(result.extraOps == [.move(from: item.id.path, to: moved.path)])
        #expect(result.renames.resolve(item.id) == moved)
    }

    /// A finished item keeps its place in `Done/` when it is renamed (L3).
    @Test func renamingAFinishedItemStaysInsideTheDoneFolder() throws {
        let item = TestVault.listItem("Read", "Sapiens", finished: true)
        let result = try Reducer.reduce(
            vault(items: [item]), .updateListItem(item.id, title: "Sapiens 2015", notes: ""),
            env: env)
        #expect(result.extraOps
            == [.move(from: item.id.path, to: "Lists/Read/Done/Sapiens 2015.md")])
    }

    @Test func renamingOntoAnExistingItemIsRefusedRatherThanOverwriting() {
        let a = TestVault.listItem("Read", "Sapiens")
        let b = TestVault.listItem("Read", "Why we sleep")
        #expect(TestVault.error(vault(items: [a, b]),
                                .updateListItem(a.id, title: "Why we sleep", notes: ""))
            == .titleCollision("Why we sleep"))
    }

    @Test func anEmptyTitleIsRefused() {
        let item = TestVault.listItem("Read", "Sapiens")
        #expect(TestVault.error(vault(items: [item]),
                                .updateListItem(item.id, title: "  ", notes: ""))
            == .invalid("A title is required"))
    }

    @Test func editingAnUnknownItemIsRefused() {
        let ghost = NoteID(path: "Lists/Read/Ghost.md")
        #expect(TestVault.error(vault(), .updateListItem(ghost, title: "x", notes: ""))
            == .notFound(ghost))
    }

    // MARK: - completeListItem (L3)

    @Test func finishingAnItemMovesItIntoTheListsDoneFolder() throws {
        let item = TestVault.listItem("Read", "Sapiens")
        let result = try Reducer.reduce(vault(items: [item]), .completeListItem(item.id), env: env)

        let done = NoteID(path: "Lists/Read/Done/Sapiens.md")
        #expect(result.snapshot.listItem(done)?.isFinished == true)
        #expect(result.snapshot.listItem(item.id) == nil)
        #expect(result.extraOps == [.move(from: item.id.path, to: done.path)])
        #expect(result.renames.resolve(item.id) == done)
    }

    @Test func finishingAnAlreadyFinishedItemChangesNothing() throws {
        let item = TestVault.listItem("Read", "Sapiens", finished: true)
        let start = vault(items: [item])
        let result = try Reducer.reduce(start, .completeListItem(item.id), env: env)
        #expect(result.snapshot == start)
        #expect(result.extraOps.isEmpty)
    }

    @Test func finishingAnItemWhoseNameIsTakenInDoneIsRefused() {
        let open = TestVault.listItem("Read", "Sapiens")
        let old = TestVault.listItem("Read", "Sapiens", finished: true)
        #expect(TestVault.error(vault(items: [open, old]), .completeListItem(open.id))
            == .titleCollision("Sapiens"))
    }

    @Test func finishingAnUnknownItemIsRefused() {
        let ghost = NoteID(path: "Lists/Read/Ghost.md")
        #expect(TestVault.error(vault(), .completeListItem(ghost)) == .notFound(ghost))
    }

    // MARK: - trashListItem (I4c)

    @Test func trashingAnItemNamesNoPathSoTheDiffMovesItToTheTrash() throws {
        let item = TestVault.listItem("Read", "Sapiens")
        let result = try Reducer.reduce(vault(items: [item]), .trashListItem(item.id), env: env)
        #expect(result.snapshot.listItems.isEmpty)
        // ARCHITECTURE §4: a removed entity nobody spoke for becomes a move into `GTD/Trash/`.
        #expect(result.extraOps.isEmpty)
    }

    @Test func trashingAnUnknownItemIsRefused() {
        let ghost = NoteID(path: "Lists/Read/Ghost.md")
        #expect(TestVault.error(vault(), .trashListItem(ghost)) == .notFound(ghost))
    }

    // MARK: - moveActionToList (E3)

    /// The action's note moves into the list folder; its body becomes the item's notes.
    @Test func anActionDroppedOnAListBecomesAnItemOfIt() throws {
        let action = TestVault.action("Read Dune", .someday, why: "Everyone says so.", what: "Borrow it.")
        let result = try Reducer.reduce(
            vault(actions: [action]), .moveActionToList(action.id, list: "Read"), env: env)
        let item = try #require(result.snapshot.listItems.first { $0.list == "Read" })
        #expect(item.title == "Read Dune")
        #expect(item.id == TestVault.layout.listItemPath(list: "Read", title: "Read Dune"))
        #expect(!item.isFinished)
        #expect(item.created == action.created)
        #expect(item.notes == "# Why?\nEveryone says so.\n\n# What?\nBorrow it.")
        #expect(result.snapshot.action(action.id) == nil)
        #expect(result.extraOps == [.move(from: action.id.path, to: item.id.path)])
        #expect(result.renames.pairs.contains { $0.old == action.id && $0.new == item.id })
        #expect(Rules.isUndoable(.moveActionToList(action.id, list: "Read")))
    }

    @Test func droppingOnAnUnknownListIsRefused() {
        let action = TestVault.action("Read Dune", .someday)
        #expect(TestVault.error(vault(actions: [action]), .moveActionToList(action.id, list: "Nope"))
            == .invalid("Unknown list: Nope"))
    }

    @Test func droppingOnAListThatAlreadyHasThatTitleIsRefused() {
        let action = TestVault.action("Read Dune", .someday)
        let taken = TestVault.listItem("Read", "Read Dune")
        #expect(TestVault.error(
            vault(items: [taken], actions: [action]), .moveActionToList(action.id, list: "Read"))
            == .titleCollision("Read Dune"))
    }

    @Test func droppingAMissingActionIsNotFound() {
        let id = TestVault.actionID("Ghost")
        #expect(TestVault.error(vault(), .moveActionToList(id, list: "Read")) == .notFound(id))
    }

    // MARK: - promoteListItem (L4)

    @Test func makingAnActionMovesTheNoteIntoActions() throws {
        let item = TestVault.listItem("Read", "Sapiens", created: -20, notes: "Marie's copy")
        let result = try Reducer.reduce(
            vault(items: [item]),
            .promoteListItem(item.id, ActionDraft(
                title: "Read Sapiens", status: .next, contexts: ["deep-work"], timeEstimate: 60,
                why: "Marie keeps asking", what: "Read the first 50 pages")),
            env: env)

        let action = try #require(result.snapshot.action(TestVault.actionID("Read Sapiens")))
        #expect(action.status == .next)
        // The note keeps its capture date — nothing pretends to be new.
        #expect(action.created == item.created)
        #expect(result.snapshot.listItems.isEmpty)
        #expect(result.extraOps == [.move(from: item.id.path, to: action.id.path)])
        #expect(result.renames.resolve(item.id) == action.id)
    }

    /// L4 — "exactly the rules of an inbox action filing": the cap is one of them (I4, D14).
    @Test func promotingIntoAFullNextIsRefusedWithTheCapError() throws {
        var full = TestVault.nextOccupied(15)
        full.lists = [GTDList(name: "Read")]
        let item = TestVault.listItem("Read", "Sapiens")
        full.listItems = [item]

        #expect(TestVault.error(full, .promoteListItem(item.id, ActionDraft(
            title: "Read Sapiens", status: .next, contexts: ["deep-work"], timeEstimate: 60,
            why: "Marie keeps asking", what: "Read it")))
            == .nextCapReached(cap: 15))
        // Someday is not a commitment, so the same item goes there without a fight.
        #expect(TestVault.error(full, .promoteListItem(item.id, ActionDraft(
            title: "Read Sapiens", status: .someday, what: "Read it")))
            == nil)
    }

    @Test func promotingOntoAnExistingActionTitleIsRefused() {
        let item = TestVault.listItem("Read", "Sapiens")
        let clash = TestVault.action("Read Sapiens", .next)
        #expect(TestVault.error(
            vault(items: [item], actions: [clash]),
            .promoteListItem(item.id, ActionDraft(
                title: "Read Sapiens", status: .someday, what: "Read it")))
            == .titleCollision("Read Sapiens"))
    }

    @Test func promotingAnUnknownItemIsRefused() {
        let ghost = NoteID(path: "Lists/Read/Ghost.md")
        #expect(TestVault.error(vault(), .promoteListItem(ghost, ActionDraft(title: "x")))
            == .notFound(ghost))
    }

    // MARK: - InboxDecision.list (I4b)

    private var capture: InboxItem {
        TestVault.inboxItem("Sapiens by Yuval Noah Harari", created: 0)
    }

    @Test func filingACaptureToAListMovesTheCaptureFile() throws {
        let item = capture
        let result = try Reducer.reduce(
            vault(inbox: [item]),
            .fileInbox(item.id, .list(name: "Read", notes: "Marie's copy")),
            env: env)

        let target = NoteID(path: "Lists/Read/Sapiens by Yuval Noah Harari.md")
        let filed = try #require(result.snapshot.listItem(target))
        #expect(filed.list == "Read")
        #expect(filed.notes == "Marie's copy")
        #expect(filed.isFinished == false)
        #expect(filed.created == item.created)
        #expect(result.snapshot.inbox.isEmpty)
        #expect(result.extraOps == [.move(from: item.id.path, to: target.path)])
    }

    /// R-4 — nothing the user dictated is dropped: a capture the title cannot hold in full
    /// keeps its whole text above the notes. Here the title holds it, so the body stays empty.
    @Test func aCaptureWhoseTitleSaysItAllGetsAnEmptyBody() throws {
        let item = capture
        let result = try Reducer.reduce(
            vault(inbox: [item]), .fileInbox(item.id, .list(name: "Read", notes: "")), env: env)
        #expect(result.snapshot.listItems.first?.notes == "")
    }

    @Test func filingToAnUnknownListIsRefused() {
        let item = capture
        #expect(TestVault.error(
            vault(inbox: [item]), .fileInbox(item.id, .list(name: "Wish", notes: "")))
            == .invalid("Unknown list: Wish"))
    }

    @Test func filingOntoAnExistingItemIsRefused() {
        let item = capture
        let existing = TestVault.listItem("Read", "Sapiens by Yuval Noah Harari")
        #expect(TestVault.error(
            vault(items: [existing], inbox: [item]),
            .fileInbox(item.id, .list(name: "Read", notes: "")))
            == .titleCollision("Sapiens by Yuval Noah Harari"))
    }

    /// L1 — a list item is not a commitment, so filing one never runs into the Next cap.
    @Test func filingToAListAtTheCapIsAllowed() throws {
        var full = TestVault.nextOccupied(15)
        full.lists = [GTDList(name: "Read")]
        let item = capture
        full.inbox = [item]
        #expect(TestVault.error(full, .fileInbox(item.id, .list(name: "Read", notes: ""))) == nil)
    }

    // MARK: - Undo (N6)

    @Test func everyListCommandThatTouchesANoteIsUndoable() {
        let id = NoteID(path: "Lists/Read/Sapiens.md")
        #expect(Rules.isUndoable(.renameList(from: "Read", to: "Reading")))
        #expect(Rules.isUndoable(.removeList(name: "Read")))
        #expect(Rules.isUndoable(.updateListItem(id, title: "x", notes: "")))
        #expect(Rules.isUndoable(.completeListItem(id)))
        #expect(Rules.isUndoable(.trashListItem(id)))
        #expect(Rules.isUndoable(.promoteListItem(id, ActionDraft(title: "x"))))
        #expect(Rules.isUndoable(.fileInbox(id, .list(name: "Read", notes: ""))))
    }

    /// `createList` only makes an empty folder, and undoing it would mean removing a directory —
    /// the hard delete this app never does (ARCHITECTURE §6). Favourites are settings, like
    /// `updateConfig`.
    @Test func creatingAListAndChoosingFavouritesAreNotUndoable() {
        #expect(!Rules.isUndoable(.createList(name: "Wish")))
        #expect(!Rules.isUndoable(.setFavouriteLists(["Read"])))
    }
}
