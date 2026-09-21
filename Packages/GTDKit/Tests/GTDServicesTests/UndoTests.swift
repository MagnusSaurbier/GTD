import Foundation
import GTDFixtures
import GTDModel
import GTDServices
import GTDVault
import Testing

/// N6 — undo the last filing or status change, and refuse rather than fight a synced vault.
@Suite("Undo")
struct UndoTests {

    @Test func undoRestoresTheVaultByteForByte() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.filesOutsideTheTrash()
        let start = await vault.backend.currentSnapshot()
        let item = try #require(start.inbox.first { $0.text.hasPrefix("call the Hausverwaltung") })

        _ = try await vault.backend.perform(.fileInbox(item.id, .action(ActionDraft(
            title: "ignored — R-4 names the note after the capture",
            status: .next,
            contexts: ["mac"],
            timeEstimate: 10,
            why: "The handle has been broken for two weeks.",
            what: "Ask for a repair date."))))
        #expect(try vault.filesOutsideTheTrash() != before)
        #expect(await vault.backend.undoLabel() == "Filed to Next")

        try await vault.backend.undo()

        #expect(try vault.filesOutsideTheTrash() == before, "every file is back, byte for byte")
        // R-4 — filing *moved* the capture into `Actions/`, so undoing it is a move back and
        // leaves no tombstone behind at all.
        #expect(try vault.files().keys.filter { $0.hasPrefix("GTD/Trash/") }.isEmpty)
        #expect(await vault.backend.undoLabel() == nil)
        #expect(SnapshotShape(try vault.rescan()) == SnapshotShape(start))
        // Visible immediately: `AppModel.undo()` reads `currentSnapshot()` right after.
        #expect(SnapshotShape(await vault.backend.currentSnapshot()) == SnapshotShape(start))
    }

    /// I4c — trashing an action through the whole stack: the note file leaves `Actions/` and
    /// turns up in `GTD/Trash/`, nothing is hard-deleted, no `status: trash` is written, and
    /// undo puts the file back byte for byte.
    @Test func trashingAnActionMovesTheFileToTheTrashAndUndoBringsItBack() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.files()
        let action = try #require(await vault.backend.currentSnapshot().actions.first {
            $0.title == "Buy a birthday present for Jonas"
        })
        let original = try #require(try vault.text(action.id.path))

        _ = try await vault.backend.perform(.trashAction(action.id))

        #expect(try vault.text(action.id.path) == nil)
        let trashed = try #require(try vault.text("GTD/Trash/Buy a birthday present for Jonas.md"))
        #expect(trashed == original, "the note is moved, not rewritten")
        #expect(!trashed.contains("status: trash"))
        #expect(await vault.backend.currentSnapshot().action(action.id) == nil)
        #expect(await vault.backend.undoLabel() == "Moved to Trash")

        try await vault.backend.undo()
        #expect(try vault.files() == before)
        #expect(await vault.backend.currentSnapshot().action(action.id) != nil)
    }

    @Test func undoRestoresARenameAndTheLinksThatFollowedIt() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.files()
        var action = try #require(await vault.backend.currentSnapshot().actions.first {
            $0.title == "Compare Erasmus partner universities"
        })
        action.title = "Compare Erasmus partners"
        _ = try await vault.backend.perform(.updateAction(action))

        try await vault.backend.undo()

        #expect(try vault.files() == before)
    }

    /// N3 — the file changed under us. Undo is refused, with the path, and nothing is written.
    @Test func undoIsRefusedAfterTheFileChangedRemotely() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let action = try #require(await vault.backend.currentSnapshot().actions.first {
            $0.title == "Book the dentist appointment"
        })
        _ = try await vault.backend.perform(.setStatus(action.id, .waiting, waiting: WaitingInfo(
            who: "Praxis", followUp: Fixtures.today.adding(days: 3))))

        // Obsidian on another device edits the very note the undo would overwrite.
        let root = try #require(vault.root)
        let url = root.appendingPathComponent(action.id.path)
        let edited = try String(contentsOf: url, encoding: .utf8) + "\nA note from the iPad.\n"
        try edited.write(to: url, atomically: true, encoding: .utf8)
        let after = try vault.files()

        await #expect(throws: ServiceError.undoStale(path: action.id.path)) {
            try await vault.backend.undo()
        }
        #expect(try vault.files() == after, "the refused undo wrote nothing")
        #expect(await vault.backend.undoLabel() == "Moved to Waiting",
                "the entry stays — the user can retry once the vault settles")
    }

    /// The same protection for a file the undo would move *back* onto: if something took that
    /// name in the meantime, undoing would either overwrite it or fail mid-transaction.
    @Test func undoIsRefusedWhenSomethingTookTheOldName() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        var action = try #require(await vault.backend.currentSnapshot().actions.first {
            $0.title == "Cancel the gym membership"
        })
        let oldPath = action.id.path
        action.title = "Cancel the gym contract"
        _ = try await vault.backend.perform(.updateAction(action))

        let root = try #require(vault.root)
        try "---\nstatus: someday\n---\n# What?\nSomething else entirely.\n"
            .write(to: root.appendingPathComponent(oldPath), atomically: true, encoding: .utf8)

        await #expect(throws: ServiceError.undoStale(path: oldPath)) {
            try await vault.backend.undo()
        }
    }

    @Test func settingsRoutineLogsAndReviewsAreNotUndoable() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()

        let action = try #require(start.actions.first { $0.title == "Order the new passport photo" })
        _ = try await vault.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        #expect(await vault.backend.undoLabel() == "Moved to Someday")

        var config = start.config
        config.nextCap = 12
        _ = try await vault.backend.perform(.updateConfig(config))
        let routine = try #require(start.routines.first)
        _ = try await vault.backend.perform(
            .logRoutineStep(routine: routine.id, stepID: routine.steps[0].id, .done))
        _ = try await vault.backend.perform(.saveWeeklyReview(WeeklyReview(year: 2026, week: 38)))

        #expect(await vault.backend.undoLabel() == "Moved to Someday",
                "none of the three entered the journal (N6)")
    }

    /// Device-local and persisted: the journal is still there after a relaunch, and the undo
    /// still works — it is the file paths and hashes that matter, not the process.
    @Test func theJournalSurvivesARelaunch() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.files()
        let action = try #require(await vault.backend.currentSnapshot().actions.first {
            $0.title == "Return the library books"
        })
        _ = try await vault.backend.perform(.setStatus(action.id, .someday, waiting: nil))

        // A new process: new store, new backend, same device-local directory.
        let root = try #require(vault.root)
        let store = FileVaultStore(
            fileSystem: PlainFileSystem(root: root),
            watcher: NullVaultWatcher(),
            today: { Fixtures.today })
        let relaunched = VaultBackend(
            store: store,
            deviceID: "test-device",
            journal: UndoJournal(directory: vault.stateDirectory),
            stateDirectory: vault.stateDirectory,
            env: { Fixtures.reducerEnv(deviceID: "test-device") })

        #expect(await relaunched.undoLabel() == "Moved to Someday")
        try await relaunched.undo()
        #expect(try vault.files() == before)
    }

    /// The journal keeps 20 entries, so ⌘Z walks back through the session. Each step is checked
    /// against the files on its own, so a stale one stops the walk instead of corrupting it.
    @Test func undoWalksBackMoreThanOneStep() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.files()
        let start = await vault.backend.currentSnapshot()
        let first = try #require(start.actions.first { $0.title == "Buy a birthday present for Jonas" })
        let second = try #require(start.actions.first { $0.title == "Book the dentist appointment" })

        _ = try await vault.backend.perform(.setStatus(first.id, .someday, waiting: nil))
        _ = try await vault.backend.perform(.setStatus(second.id, .someday, waiting: nil))

        try await vault.backend.undo()
        #expect(await vault.backend.undoLabel() == "Moved to Someday")
        try await vault.backend.undo()

        #expect(try vault.files() == before)
        await #expect(throws: ServiceError.nothingToUndo) { try await vault.backend.undo() }
    }

    @Test func theJournalKeepsAtMostTwentyEntries() async throws {
        let directory = TestVault.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = UndoJournal(directory: directory)
        for index in 1...25 {
            await journal.push(UndoJournal.Entry(
                label: "Entry \(index)", inverseOps: [], hashes: [:]))
        }
        #expect(await journal.count == 20)
        #expect(await journal.peek()?.label == "Entry 25")

        let reopened = UndoJournal(directory: directory)
        #expect(await reopened.count == 20)
        #expect(await reopened.pop()?.label == "Entry 25")
        #expect(await reopened.peek()?.label == "Entry 24")
    }
}
