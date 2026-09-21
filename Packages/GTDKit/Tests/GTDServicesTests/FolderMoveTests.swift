import Foundation
import GTDFixtures
import GTDModel
import GTDVault
import Testing
@testable import GTDServices

/// R-5 — the folder move seen from `GTDServices`: what the undo journal hashes, and what happens
/// when the destination is taken.
///
/// This is the one suite in `GTDServicesTests` that reaches past the public API (`@testable`).
/// The collision policy is a private step inside `perform`, and no `GTDCommand` emits a
/// `.moveFolder` yet — the commands that will are T03 (rename/remove a list) and T05 (change a
/// project's area). Rather than wait for them, the policy is tested where it lives; the *undo*
/// half below needs no such help and goes through the real `VaultBackend`.
@Suite("Folder moves through GTDServices (R-5)")
struct FolderMoveTests {

    // MARK: Undo safety — the files inside the folder

    /// N3 §7.6 for a moved tree: the undo journal hashes the files **inside** the folder, so an
    /// edit that landed inside it in the meantime refuses the undo instead of being carried back
    /// to the old path unnoticed.
    @Test func undoIsRefusedWhenAFileInsideTheMovedFolderChanged() async throws {
        let vault = FolderMoveVault()
        defer { vault.cleanUp() }
        try await vault.backend.start()

        try await vault.moveFolderWithTheNextCommand(
            from: "Projects/Applications/DAAD", to: "GTD/Trash/DAAD")
        #expect(vault.fileSystem.exists("GTD/Trash/DAAD/Transcript.pdf"))

        // Obsidian on another device edits a note that travelled with the folder.
        vault.fileSystem.writeIgnoringFailures("edited elsewhere", to: "GTD/Trash/DAAD/DAAD.md")

        await #expect(throws: ServiceError.undoStale(path: "GTD/Trash/DAAD/DAAD.md")) {
            try await vault.backend.undo()
        }
        // Refused means refused: nothing moved back.
        #expect(vault.fileSystem.exists("GTD/Trash/DAAD/DAAD.md"))
        #expect(!vault.fileSystem.folderExists("Projects/Applications/DAAD"))
    }

    @Test func undoOfAFolderMoveCarriesTheWholeTreeBack() async throws {
        let vault = FolderMoveVault()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = vault.fileSystem.snapshotOfFiles

        try await vault.moveFolderWithTheNextCommand(
            from: "Projects/Applications/DAAD", to: "GTD/Trash/DAAD")
        #expect(vault.fileSystem.snapshotOfFiles != before)

        try await vault.backend.undo()

        #expect(vault.fileSystem.snapshotOfFiles == before, "every file is back, byte for byte")
        #expect(!vault.fileSystem.folderExists("GTD/Trash/DAAD"))
    }

    /// A file that appeared *beside* the moved folder is not one of the files the undo would
    /// carry back, so it does not make the undo stale.
    @Test func anEditOutsideTheMovedFolderDoesNotBlockTheUndo() async throws {
        let vault = FolderMoveVault()
        defer { vault.cleanUp() }
        try await vault.backend.start()

        try await vault.moveFolderWithTheNextCommand(
            from: "Projects/Applications/DAAD", to: "GTD/Trash/DAAD")
        vault.fileSystem.writeIgnoringFailures("a new knowledge note", to: "Knowledge/Neu.md")

        try await vault.backend.undo()
        #expect(vault.fileSystem.exists("Projects/Applications/DAAD/DAAD.md"))
    }

    // MARK: The collision policy

    /// R-5 — "remove list" is a folder move into `GTD/Trash/`, and the same list may be removed,
    /// re-created and removed again. App-owned folders take a free name rather than failing.
    @Test func aFolderMoveIntoTheTrashGetsAFreeName() async throws {
        let vault = FolderMoveVault(extraFiles: ["GTD/Trash/Read/Dune.md": "an older casualty"])
        defer { vault.cleanUp() }
        try await vault.backend.start()

        let resolved = try await vault.backend.resolveCollisions(
            [.moveFolder(from: "Lists/Read", to: "GTD/Trash/Read")], layout: .default)

        #expect(resolved == [.moveFolder(from: "Lists/Read", to: "GTD/Trash/Read 2")])
        #expect(try await vault.store.read(path: "GTD/Trash/Read/Dune.md") == "an older casualty")
    }

    /// Anywhere else a taken destination is the user's to resolve — renaming a list onto a name
    /// that is already a list, say.
    @Test func aFolderMoveOntoATakenNameOutsideTheAppFoldersIsACollision() async throws {
        let vault = FolderMoveVault(extraFiles: ["Lists/Watch/Solaris.md": "x"])
        defer { vault.cleanUp() }
        try await vault.backend.start()

        await #expect(throws: GTDError.titleCollision("Watch")) {
            try await vault.backend.resolveCollisions(
                [.moveFolder(from: "Lists/Read", to: "Lists/Watch")], layout: .default)
        }
    }

    /// A free destination is left exactly as it is — the policy only ever renames around a
    /// collision, never "just in case".
    @Test func aFreeFolderDestinationIsUntouched() async throws {
        let vault = FolderMoveVault()
        defer { vault.cleanUp() }
        try await vault.backend.start()

        let ops: [VaultFileOp] = [.moveFolder(from: "Lists/Read", to: "Lists/Reading")]
        #expect(try await vault.backend.resolveCollisions(ops, layout: .default) == ops)
    }
}

// MARK: - Harness

/// A vault whose store smuggles one folder move into the next commit.
///
/// No command emits `.moveFolder` until T03/T05, so this is how the primitive is driven through
/// the **real** backend path: `VaultBackend` commits, the move rides along, and the inverse the
/// backend hashes and pushes onto the undo journal is the real one.
private struct FolderMoveVault {
    let fileSystem: InMemoryFileSystem
    let store: FolderMovingStore
    let backend: VaultBackend
    let stateDirectory: URL

    init(extraFiles: [String: String] = [:]) {
        var files = SampleVault.files
        // Something inside the project folder that the index ignores: a folder move takes every
        // file with it, not only the notes the snapshot knows about.
        files["Projects/Applications/DAAD/Transcript.pdf"] = "%PDF"
        for (path, text) in extraFiles { files[path] = text }
        fileSystem = InMemoryFileSystem(files: files)
        let base = FileVaultStore(
            fileSystem: fileSystem, watcher: NullVaultWatcher(), today: { Fixtures.today })
        store = FolderMovingStore(base)
        stateDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GTDFolderMoveTests-\(UUID().uuidString)", isDirectory: true)
        backend = VaultBackend(
            store: store,
            deviceID: "test-device",
            journal: UndoJournal(directory: stateDirectory),
            stateDirectory: stateDirectory,
            env: { Fixtures.reducerEnv(deviceID: "test-device") })
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: stateDirectory)
    }

    /// Runs one ordinary, undoable command with the folder move attached to its commit.
    func moveFolderWithTheNextCommand(from: String, to: String) async throws {
        await store.moveFolderOnNextCommit(from: from, to: to)
        let action = try #require(await backend.currentSnapshot().actions.first {
            $0.title == "Return the library books"
        })
        _ = try await backend.perform(.setStatus(action.id, .someday, waiting: nil))
    }
}

/// Forwards everything to a real `FileVaultStore`, prepending one `.moveFolder` to the next
/// `commit`. Nothing else about the stack is faked.
private actor FolderMovingStore: VaultStore {
    private let base: FileVaultStore
    private var pending: (from: String, to: String)?

    init(_ base: FileVaultStore) { self.base = base }

    func moveFolderOnNextCommit(from: String, to: String) {
        pending = (from: from, to: to)
    }

    nonisolated func snapshots() -> AsyncStream<VaultSnapshot> { base.snapshots() }

    func read(path: String) async throws -> String? { try await base.read(path: path) }

    func folderContents(_ folder: String) async throws -> [String]? {
        try await base.folderContents(folder)
    }

    func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp] {
        guard let move = pending else { return try await base.commit(ops) }
        pending = nil
        return try await base.commit([.moveFolder(from: move.from, to: move.to)] + ops)
    }

    func activate() async throws { try await base.activate() }
}
