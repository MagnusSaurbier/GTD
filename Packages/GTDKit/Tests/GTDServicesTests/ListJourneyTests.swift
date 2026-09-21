import Testing
import Foundation
import GTDModel
import GTDMarkdown
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// §5a end to end, through the **real** stack — `AppModel` → `VaultBackend` → `FileVaultStore`
/// → `PlainFileSystem` over a temp copy of the sample vault. The assertions are about the
/// **files**: a list is a folder, an item is a note, `Done/` is a folder inside it, and every
/// step is undoable. Never the real vault (CLAUDE.md rule 1).
@MainActor
@Suite struct ListJourneyTests {

    /// Capture → file into a list → finish it → undo → make an action at the cap (refused) →
    /// demote one → make the action → it lands in Next.
    @Test func aCaptureBecomesAListItemAndThenAnAction() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        #expect(Rules.lists(model.snapshot).map(\.name) == ["Read", "Watch", "Wish"])
        #expect(Rules.listRows(model.snapshot).first { $0.list.name == "Read" }?.openCount == 3)

        // ── 1. A capture is filed into a list (I4b) ───────────────────────────────────────────
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(
            text: "Der Report über Wohnungsmärkte, den Marie empfohlen hat",
            at: Fixtures.date(Fixtures.today, 9, 30))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { snapshot in snapshot.inbox.contains { $0.id == captured } }

        try await model.send(.fileInbox(captured, .list(
            name: "Read",
            notes: "Marie hat ihn in der WhatsApp-Gruppe geteilt.")))

        // R-4 — the item is named after the capture text (it fits, so nothing is repeated in
        // the body); the notes panel is the body.
        let itemPath = "Lists/Read/Der Report über Wohnungsmärkte, den Marie empfohlen hat.md"
        let itemText = try #require(try vault.text(itemPath))
        #expect(try vault.text(captured.path) == nil, "the capture file left the inbox")
        #expect(itemText.contains("created: 2026-09-19T09:30:00+02:00"),
                "the capture's own timestamp travels with the file (C3)")
        #expect(itemText.contains("Marie hat ihn in der WhatsApp-Gruppe geteilt."))
        #expect(!itemText.contains("status:"), "a list item is not a commitment (L1)")
        #expect(model.undoLabel == "Added to Read")
        #expect(Rules.openListItemCount(model.snapshot) == 7)

        // ── 2. Finishing it moves the note into `Done/` (L3) ──────────────────────────────────
        let itemID = NoteID(path: itemPath)
        let trashBefore = try vault.files().keys.filter { $0.hasPrefix("GTD/Trash/") }
        try await model.send(.completeListItem(itemID))
        let donePath = "Lists/Read/Done/Der Report über Wohnungsmärkte, den Marie empfohlen hat.md"
        #expect(try vault.text(itemPath) == nil)
        #expect(try vault.text(donePath) == itemText, "the note is kept as a log, byte for byte")
        // L3 is a *move*: the note is not re-created in `Done/` with the original swept away.
        #expect(try vault.files().keys.filter { $0.hasPrefix("GTD/Trash/") } == trashBefore,
                "finishing an item moves its note; it never writes a copy and trashes the original")
        #expect(model.undoLabel == "Done")
        #expect(Rules.listItems(model.snapshot, in: "Read", finished: true).count == 2)

        // ── 3. Undo puts it back where it was (N6) ────────────────────────────────────────────
        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(donePath) == nil)
        #expect(try vault.text(itemPath) == itemText)
        #expect(model.snapshot.listItem(itemID)?.isFinished == false)

        // ── 4. Make action at the cap: refused, and nothing is written (L4, I4/D14) ───────────
        // The sample vault sits at 14 of 15; one filing takes it to the cap exactly.
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == 14)
        // R-3 — promoting into Next needs Why?, What?, a context and a time estimate, so the
        // filler is a note that already carries them.
        let filler = try #require(model.snapshot.actions.first {
            $0.status == .someday && !$0.why.isEmpty && !$0.what.isEmpty
                && !$0.contexts.isEmpty && $0.timeEstimate != nil
        })
        try await model.send(.setStatus(filler.id, .next, waiting: nil))
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == 15)

        let bytesAtCap = try vault.filesOutsideTheTrash()
        let draft = ActionDraft(
            title: "Read the Wohnungsmarkt report",
            status: .next,
            contexts: ["deep-work"],
            timeEstimate: 60,
            why: "Marie asks about it every week.",
            what: "Read the summary and the chapter on Munich.")
        await #expect(throws: GTDError.nextCapReached(cap: 15)) {
            try await model.send(.promoteListItem(itemID, draft))
        }
        #expect(try vault.filesOutsideTheTrash() == bytesAtCap, "a refused promotion writes nothing")
        #expect(try vault.text(itemPath) == itemText, "the item is still in its list")

        // ── 5. Demote one, then the same promotion goes through (L4) ─────────────────────────
        try await model.send(.setStatus(filler.id, .someday, waiting: nil))
        try await model.send(.promoteListItem(itemID, draft))

        let actionPath = "Actions/Read the Wohnungsmarkt report.md"
        #expect(try vault.text(itemPath) == nil, "the note moved out of the list")
        let actionText = try #require(try vault.text(actionPath))
        #expect(actionText.contains("status: next"))
        #expect(actionText.contains("contexts: [deep-work]"))
        #expect(actionText.contains("timeEstimate: 60"))
        #expect(actionText.contains("created: 2026-09-19T09:30:00+02:00"),
                "the note kept its own timestamp across two moves")
        // L4 moves the note, so nothing the user wrote about it is lost on the way.
        #expect(actionText.contains("Marie hat ihn in der WhatsApp-Gruppe geteilt."))
        #expect(actionText.contains("# Why?\nMarie asks about it every week."))
        #expect(model.undoLabel == "Filed to Next")

        // ── 6. A cold re-scan of the bytes says the same thing ───────────────────────────────
        let rescanned = try vault.rescan()
        #expect(rescanned.action(NoteID(path: actionPath))?.status == .next)
        #expect(rescanned.listItem(itemID) == nil)
        #expect(Rules.countsTowardCap(rescanned, today: Fixtures.today) == 15)
        #expect(rescanned.issues.isEmpty, "the journey left no unreadable file behind")
        // L6 — none of it ever entered an action query as a list item.
        #expect(Rules.lists(rescanned).map(\.name) == ["Read", "Watch", "Wish"])
        #expect(Rules.openListItemCount(rescanned) == 6)
    }

    /// L2/R-5 — the three folder commands, against the files: create, rename, remove, undo.
    @Test func listsAreFoldersAndTheAppMovesThemAsSuch() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        // Create: a folder, and nothing else.
        try await model.send(.createList(name: "Listen to"))
        #expect(try await vault.store.folderContents("Lists/Listen to") == [])
        #expect(model.snapshot.list(named: "Listen to") != nil)
        #expect(try vault.files().keys.contains { $0.hasPrefix("Lists/Listen to/") } == false)

        // Rename: one folder move, items included.
        let before = try #require(try vault.text("Lists/Read/Thinking Fast and Slow.md"))
        try await model.send(.renameList(from: "Read", to: "Reading"))
        #expect(try vault.text("Lists/Read/Thinking Fast and Slow.md") == nil)
        #expect(try vault.text("Lists/Reading/Thinking Fast and Slow.md") == before)
        #expect(try vault.text(
            "Lists/Reading/Done/Designing Data-Intensive Applications.md") != nil,
            "the Done/ log travelled with the folder (L3)")
        #expect(model.snapshot.list(named: "Read") == nil)

        // Favourites follow the vault, not a stale name.
        try await model.send(.setFavouriteLists(["Reading", "Watch"]))
        let config = try #require(try vault.text("GTD/Config.md"))
        #expect(config.contains("favouriteLists: [Reading, Watch]"))

        // Remove: into the trash, never deleted — and undoable in one step.
        try await model.send(.removeList(name: "Watch"))
        #expect(try await vault.store.folderContents("Lists/Watch") == nil)
        #expect(try vault.text("GTD/Trash/Watch/Arrival.md") != nil)
        #expect(model.snapshot.list(named: "Watch") == nil)
        #expect(model.undoLabel == "Removed list")

        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text("Lists/Watch/Arrival.md") != nil)
        #expect(try vault.text("GTD/Trash/Watch/Arrival.md") == nil)

        // And the rename undoes too, byte for byte.
        try await model.send(.renameList(from: "Reading", to: "Read"))
        #expect(try vault.text("Lists/Read/Thinking Fast and Slow.md") == before)

        let rescanned = try vault.rescan()
        #expect(Rules.lists(rescanned).map(\.name) == ["Listen to", "Read", "Watch", "Wish"])
        #expect(rescanned.issues.isEmpty)
    }

    /// I4b `More…` › `New list…` — what `InboxSession.createListAndFile` sends, against the
    /// files: the folder is made, the capture lands in it, and undo takes the capture back out
    /// while the (now empty) list stays, because `createList` has no inverse.
    @Test func aCaptureIsFiledIntoAListCreatedForIt() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(
            text: "Espresso tamper, 58 mm", at: Fixtures.date(Fixtures.today, 9, 30))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { snapshot in snapshot.inbox.contains { $0.id == captured } }

        try await model.send(.createList(name: "Buy"))
        try await model.send(.fileInbox(captured, .list(name: "Buy", notes: "")))
        #expect(try vault.text("Lists/Buy/Espresso tamper, 58 mm.md") != nil)
        #expect(try vault.text(captured.path) == nil)
        #expect(model.undoLabel == "Added to Buy")

        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(captured.path) != nil, "the capture is back in the inbox")
        #expect(try vault.text("Lists/Buy/Espresso tamper, 58 mm.md") == nil)
        #expect(try await vault.store.folderContents("Lists/Buy") == [])
        #expect(model.snapshot.list(named: "Buy") != nil)
    }

    /// I4c — a trashed item goes to `GTD/Trash/` like everything else the user throws away.
    @Test func trashingAnItemMovesItsNoteToTheTrash() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.listItems.isEmpty }

        let id = NoteID(path: "Lists/Watch/Arrival.md")
        let text = try #require(try vault.text(id.path))
        try await model.send(.trashListItem(id))
        #expect(try vault.text(id.path) == nil)
        #expect(try vault.text("GTD/Trash/Arrival.md") == text)
        #expect(model.undoLabel == "Moved to Trash")

        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(id.path) == text)
    }

    /// Renaming an item is a file move that never overwrites, and it reports the rename so an
    /// open editor follows the note (ARCHITECTURE §4).
    @Test func renamingAnItemMovesItsFileAndTravelsWithTheSnapshot() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.listItems.isEmpty }

        let id = NoteID(path: "Lists/Watch/Arrival.md")
        try await model.send(.updateListItem(id, title: "Arrival (2016)", notes: "Villeneuve"))
        let moved = try #require(try vault.text("Lists/Watch/Arrival (2016).md"))
        #expect(moved.contains("Villeneuve"))
        #expect(try vault.text(id.path) == nil)
        #expect(model.consumeRenames().resolve(id) == NoteID(path: "Lists/Watch/Arrival (2016).md"))

        // A second item cannot be renamed onto it.
        let other = NoteID(path: "Lists/Watch/The lecture recording on distributed systems.md")
        await #expect(throws: GTDError.titleCollision("Arrival (2016)")) {
            try await model.send(.updateListItem(other, title: "Arrival (2016)", notes: ""))
        }
        #expect(try vault.text(other.path) != nil, "the refused rename left the note alone")
    }

    // MARK: - Helpers

    /// Same poll as `EndToEndJourneyTests`: a store change reaches `AppModel` over three hops,
    /// so wait for the value rather than for a fixed number of turns.
    @discardableResult
    private func settle(
        _ model: AppModel, until condition: @MainActor (VaultSnapshot) -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if condition(model.snapshot) { return true }
            await Task.yield()
        }
        return condition(model.snapshot)
    }
}
