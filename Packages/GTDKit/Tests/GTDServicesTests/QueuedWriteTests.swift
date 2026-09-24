import Foundation
import GTDAppCore
import GTDFixtures
import GTDMarkdown
import GTDModel
import GTDServices
import GTDVault
import Testing

/// The production write policy: `perform` publishes and returns, the files follow on a serial
/// queue, and a refused write reverts the snapshot and is announced on `writeFailures()`.
///
/// `GatedStore` stands in for a vault whose coordinated writes take seconds (an iCloud folder
/// with a busy sync daemon): nothing is committed until the test opens the gate.
@Suite("Writes queued behind the UI")
struct QueuedWriteTests {

    @Test func aCommandReturnsAndPublishesBeforeItsFileIsWritten() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        let before = rig.fileSystem.snapshotOfFiles

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))

        // The gate is still shut: `perform` came back without a single byte written.
        #expect(rig.fileSystem.snapshotOfFiles == before)
        #expect(await rig.backend.currentSnapshot().action(action.id)?.status == .someday)
        #expect(await rig.backend.undoLabel() != nil, "undo is offered before the write landed")

        await rig.store.open()
        await rig.backend.flush()
        #expect(try rig.rescan().action(action.id)?.status == .someday)
        #expect(await rig.backend.currentSnapshot().action(action.id)?.status == .someday)
    }

    @Test func queuedCommandsBuildOnEachOtherAndLandInOrder() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        var edited = try #require(await rig.backend.currentSnapshot().action(action.id))
        #expect(edited.status == .someday, "the second command sees the first one's snapshot")
        edited.contexts = ["errands"]
        _ = try await rig.backend.perform(.updateAction(edited))
        #expect(await rig.store.commits == 0)

        await rig.store.open()
        await rig.backend.flush()
        let onDisk = try #require(try rig.rescan().action(action.id))
        #expect(onDisk.status == .someday)
        #expect(onDisk.contexts == ["errands"])
        #expect(await rig.store.commits == 2)
    }

    /// The watcher fires for write 1 while write 2 is still queued. The store's snapshot does
    /// not know write 2 yet — publishing it would take back what the person just did.
    @Test func aStoreEventDoesNotWalkTheUIBackWhileWritesAreQueued() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        await rig.store.inner.simulateChangeForTesting()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await rig.backend.currentSnapshot().action(action.id)?.status == .someday)

        await rig.store.open()
        await rig.backend.flush()
    }

    @Test func aRefusedWriteRevertsTheSnapshotAndIsReported() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        let before = rig.fileSystem.snapshotOfFiles
        let shapeBefore = SnapshotShape(await rig.backend.currentSnapshot())
        var failures = rig.backend.writeFailures().makeAsyncIterator()

        rig.fileSystem.failWrites(matching: [action.id.path])
        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        let other = try #require(await rig.backend.currentSnapshot().actions.first {
            $0.status == .next && $0.id != action.id
        })
        _ = try await rig.backend.perform(.setStatus(other.id, .someday, waiting: nil))

        await rig.store.open()
        let failure = try #require(await failures.next())
        await rig.backend.flush()

        #expect(failure.discarded == 1, "the write queued behind it was built on top of it")
        #expect(failure.reason is VaultError)
        #expect(rig.fileSystem.snapshotOfFiles == before, "nothing of either command was written")
        #expect(SnapshotShape(await rig.backend.currentSnapshot()) == shapeBefore)
        #expect(await rig.backend.undoLabel() == nil)

        // The queue is usable again afterwards.
        _ = try await rig.backend.perform(.setStatus(other.id, .someday, waiting: nil))
        await rig.backend.flush()
        #expect(try rig.rescan().action(other.id)?.status == .someday)
    }

    /// N3 — the stale-write guard under the production policy: the file changed after the
    /// command was reduced (Obsidian, a sync), so when its turn comes it is refused, the snapshot
    /// goes back to what the file says — the other writer's text included — and the refusal names
    /// the path on `writeFailures()`.
    @Test func aWriteBuiltOnAStaleSnapshotIsRefusedAndTheOtherEditKept() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        var failures = rig.backend.writeFailures().makeAsyncIterator()

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        // Behind the shut gate, "Obsidian" appends to the note the queued write would rewrite.
        let elsewhere = try #require(try rig.fileSystem.readText(action.id.path))
            + "\nA line typed elsewhere.\n"
        try rig.fileSystem.writeText(elsewhere, to: action.id.path)

        await rig.store.open()
        let failure = try #require(await failures.next())
        await rig.backend.flush()

        #expect(failure.reason as? ServiceError == .staleWrite(path: action.id.path))
        #expect(failure.description.contains("Reopen the note"), "\(failure)")
        #expect(try rig.fileSystem.readText(action.id.path) == elsewhere, "not a byte written")
        let shown = try #require(await rig.backend.currentSnapshot().action(action.id))
        #expect(shown.status == action.status, "the change was taken back off the screen")
        #expect(NoteCodec.encode(shown) == elsewhere, "and the note shows the other writer's text")
        #expect(await rig.store.commits == 0)
    }

    /// The refusal carries both versions for the conflict sheet, and `resolve` writes what the
    /// person settled on — undoable, and shown at once (ARCHITECTURE §6, 2026-09-25).
    @Test func aStaleWriteCarriesAConflictAndResolveWritesTheMergedNote() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        var failures = rig.backend.writeFailures().makeAsyncIterator()
        let base = try #require(try rig.fileSystem.readText(action.id.path))

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        let elsewhere = base + "\nA line typed elsewhere.\n"
        try rig.fileSystem.writeText(elsewhere, to: action.id.path)

        await rig.store.open()
        let failure = try #require(await failures.next())
        await rig.backend.flush()

        let conflict = try #require(failure.conflict)
        #expect(conflict.basePath == action.id.path)
        #expect(conflict.base == base)
        #expect(conflict.path == action.id.path)
        #expect(conflict.mine?.contains("status: someday") == true, "what this device wanted to write")
        #expect(conflict.theirsPath == action.id.path)
        #expect(conflict.theirs == elsewhere)
        // Two different places changed: the merge keeps both and reports no clash.
        let suggestion = conflict.suggestion
        #expect(suggestion.conflicts == 0)
        #expect(suggestion.text.contains("status: someday") && suggestion.text.contains("typed elsewhere"))

        try await rig.backend.resolve(conflict, path: suggestion.path, text: suggestion.text)
        #expect(try rig.fileSystem.readText(action.id.path) == suggestion.text)
        let shown = try #require(await rig.backend.currentSnapshot().action(action.id))
        #expect(shown.status == .someday, "the merged note is on screen without waiting for a watcher")
        #expect(await rig.backend.undoLabel() == "Merged \u{201C}\(action.id.title)\u{201D}")

        try await rig.backend.undo()
        #expect(try rig.fileSystem.readText(action.id.path) == elsewhere, "undo restores the vault's version")
    }

    /// Renamed in the vault, edited here: the conflict finds the note under its new name, the
    /// suggestion is that name with this device's text, and resolving under a third title moves
    /// the vault's file there — nothing is written back to the old path.
    @Test func aRenameElsewhereIsFoundByContentAndResolvedUnderTheChosenTitle() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        var failures = rig.backend.writeFailures().makeAsyncIterator()
        let base = try #require(try rig.fileSystem.readText(action.id.path))

        var edited = action
        edited.why = "edited here"
        _ = try await rig.backend.perform(.updateAction(edited))
        let renamedPath = "Actions/\(action.id.title) — renamed elsewhere.md"
        try rig.fileSystem.move(action.id.path, to: renamedPath)

        await rig.store.open()
        let failure = try #require(await failures.next())
        await rig.backend.flush()

        let conflict = try #require(failure.conflict)
        #expect(conflict.theirsPath == renamedPath)
        #expect(conflict.theirs == base)
        #expect(conflict.suggestion.path == renamedPath)
        #expect(conflict.suggestion.text.contains("edited here"))

        let chosen = "Actions/\(action.id.title) — settled.md"
        try await rig.backend.resolve(conflict, path: chosen, text: conflict.suggestion.text)
        #expect(try rig.fileSystem.readText(chosen) == conflict.suggestion.text)
        #expect(try rig.fileSystem.readText(renamedPath) == nil)
        #expect(try rig.fileSystem.readText(action.id.path) == nil, "the old path stays empty")
        #expect(await rig.backend.currentSnapshot().action(NoteID(path: chosen))?.why == "edited here")
        #expect(await rig.backend.currentUpdate().renames.pairs.contains {
            $0.old.path == renamedPath && $0.new.path == chosen
        }, "the shell can follow the note to its settled title")
    }

    /// A title the vault already uses is the person's to change, not ours to overwrite.
    @Test func resolvingOntoATakenTitleIsACollision() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        let other = try #require(await rig.backend.currentSnapshot().actions.first { $0.id != action.id })
        let conflict = WriteConflict(
            label: "Edit", basePath: action.id.path, base: "x", path: action.id.path, mine: "x",
            theirsPath: action.id.path, theirs: "y")
        await rig.store.open()
        await #expect(throws: GTDError.titleCollision(other.id.title)) {
            try await rig.backend.resolve(conflict, path: other.id.path, text: "merged")
        }
    }

    @Test func undoWaitsForTheQueueAndThenRestoresTheFile() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        let before = rig.fileSystem.snapshotOfFiles

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        async let undone: Void = rig.backend.undo()
        await rig.store.open()
        try await undone

        #expect(rig.fileSystem.snapshotOfFiles == before)
        #expect(await rig.backend.currentSnapshot().action(action.id)?.status == .next)
    }

    /// Undo was pressed for a change that then turned out not to be saved. Undoing the journal
    /// entry *below* it would revert something the person never asked to revert.
    @Test func undoOfAChangeThatWasNotSavedUndoesNothingElse() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let first = try await rig.nextAction()
        await rig.store.open()
        _ = try await rig.backend.perform(.setStatus(first.id, .someday, waiting: nil))
        await rig.backend.flush()
        let saved = rig.fileSystem.snapshotOfFiles

        let second = try await rig.nextAction()
        await rig.store.shut()
        rig.fileSystem.failWrites(matching: [second.id.path])
        _ = try await rig.backend.perform(.setStatus(second.id, .someday, waiting: nil))
        let backend = rig.backend
        let undo = Task { try await backend.undo() }
        // Undo has to be *waiting for the queue* when the write is refused — that is the case
        // under test. There is nothing to await for "it is waiting", hence the pause.
        try await Task.sleep(nanoseconds: 100_000_000)
        await rig.store.open()

        await #expect(throws: ServiceError.writeDiscarded) { try await undo.value }
        #expect(rig.fileSystem.snapshotOfFiles == saved, "the first command is still in the vault")
    }

    // MARK: - Nothing is written unless the person acts on an item

    @Test func openingTheVaultWritesNothing() async throws {
        let rig = try await Rig(archivedToday: false)
        defer { rig.cleanUp() }
        await rig.store.open()
        await rig.backend.flush()

        #expect(await rig.store.commits == 0, "no archive at launch, although one is due")
        #expect(rig.fileSystem.snapshotOfFiles == SampleVault.files)
    }

    @Test func theDailyArchiveRidesBehindTheFirstChangeOfTheDay() async throws {
        let rig = try await Rig(archivedToday: false)
        defer { rig.cleanUp() }
        let archived = "Archive/2026/08/Collect DAAD transcripts.md"
        await rig.store.open()

        let first = try await rig.nextAction()
        _ = try await rig.backend.perform(.setStatus(first.id, .someday, waiting: nil))
        await rig.backend.flush()
        #expect(rig.fileSystem.snapshotOfFiles[archived] != nil)
        #expect(await rig.store.commits == 2, "the person's write, then the archive")

        let second = try await rig.nextAction()
        _ = try await rig.backend.perform(.setStatus(second.id, .someday, waiting: nil))
        await rig.backend.flush()
        #expect(await rig.store.commits == 3, "once a day, not behind every write")
    }

    @Test func stopLetsTheQueuedWritesLand() async throws {
        let rig = try await Rig()
        defer { rig.cleanUp() }
        let action = try await rig.nextAction()
        await rig.store.open()

        _ = try await rig.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        await rig.backend.stop()
        #expect(try rig.rescan().action(action.id)?.status == .someday)
    }
}

// MARK: - Rig

private struct Rig {
    let fileSystem: InMemoryFileSystem
    let store: GatedStore
    let backend: VaultBackend
    let stateDirectory: URL

    /// `archivedToday` pretends the daily archive already ran, so a test sees only its own
    /// writes; the housekeeping tests pass `false`.
    init(archivedToday: Bool = true) async throws {
        fileSystem = InMemoryFileSystem(files: SampleVault.files)
        store = GatedStore(inner: FileVaultStore(
            fileSystem: fileSystem, watcher: NullVaultWatcher(), today: { Fixtures.today }))
        stateDirectory = TestVault.temporaryDirectory()
        if archivedToday {
            try Data(#"{"lastArchiveDay":"\#(Fixtures.today.iso)"}"#.utf8)
                .write(to: stateDirectory.appendingPathComponent("housekeeping.json"))
        }
        backend = VaultBackend(
            store: store,
            deviceID: "test-device",
            journal: UndoJournal(directory: stateDirectory),
            stateDirectory: stateDirectory,
            env: { Fixtures.reducerEnv(deviceID: "test-device") })
        try await backend.start()
    }

    func nextAction() async throws -> Action {
        try #require(await backend.currentSnapshot().actions.first {
            $0.status == .next && $0.project == nil
        })
    }

    func rescan() throws -> VaultSnapshot {
        var index = VaultIndex()
        try index.refresh(using: fileSystem)
        return index.snapshot(today: Fixtures.today)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: stateDirectory) }
}

/// A `VaultStore` whose commits wait at a gate — a slow vault, under the test's control.
private actor GatedStore: VaultStore {
    let inner: FileVaultStore
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var commits = 0

    init(inner: FileVaultStore) { self.inner = inner }

    func open() {
        isOpen = true
        let waiters = waiting
        waiting = []
        for waiter in waiters { waiter.resume() }
    }

    func shut() { isOpen = false }

    nonisolated func snapshots() -> AsyncStream<VaultSnapshot> { inner.snapshots() }
    func read(path: String) async throws -> String? { try await inner.read(path: path) }
    func folderContents(_ folder: String) async throws -> [String]? {
        try await inner.folderContents(folder)
    }
    func activate() async throws { try await inner.activate() }

    func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp] {
        if !isOpen { await withCheckedContinuation { waiting.append($0) } }
        commits += 1
        return try await inner.commit(ops)
    }
}
