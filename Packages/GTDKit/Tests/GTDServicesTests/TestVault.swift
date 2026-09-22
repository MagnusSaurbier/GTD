import Foundation
import GTDFixtures
import GTDModel
import GTDServices
import GTDVault

/// A throw-away vault plus the backend that writes to it.
///
/// Two flavours, because the acceptance criteria need both: `inMemory` runs the whole stack on
/// `InMemoryFileSystem` (fast, deterministic mtimes, injectable write failures), `onDisk` copies
/// the sample vault into a temp directory and drives `PlainFileSystem` over it. Neither ever
/// touches the real vault.
///
/// `writes` defaults to `.awaited` — these suites read the files straight after a command.
/// `QueuedWriteTests` is the one that runs the production policy.
struct TestVault {
    let fileSystem: any VaultFileSystem
    let store: FileVaultStore
    let backend: VaultBackend
    let journal: UndoJournal
    /// Device-local state (undo journal, housekeeping) — never inside the vault.
    let stateDirectory: URL
    /// Set for `onDisk`, so tests can remove the tree.
    let root: URL?

    static func inMemory(
        files: [String: String] = SampleVault.files,
        deviceID: String = "test-device",
        writes: WritePolicy = .awaited
    ) -> TestVault {
        make(fileSystem: InMemoryFileSystem(files: files), deviceID: deviceID, root: nil,
             writes: writes)
    }

    static func onDisk(deviceID: String = "test-device") throws -> TestVault {
        let root = try SampleVault.copyToTemporaryDirectory()
        return make(fileSystem: PlainFileSystem(root: root), deviceID: deviceID, root: root)
    }

    private static func make(
        fileSystem: any VaultFileSystem, deviceID: String, root: URL?,
        writes: WritePolicy = .awaited
    ) -> TestVault {
        let store = FileVaultStore(
            fileSystem: fileSystem,
            watcher: NullVaultWatcher(),
            today: { Fixtures.today })
        let stateDirectory = Self.temporaryDirectory()
        let journal = UndoJournal(directory: stateDirectory)
        return TestVault(
            fileSystem: fileSystem,
            store: store,
            backend: VaultBackend(
                store: store,
                deviceID: deviceID,
                journal: journal,
                stateDirectory: stateDirectory,
                env: { Fixtures.reducerEnv(deviceID: deviceID) },
                writes: writes),
            journal: journal,
            stateDirectory: stateDirectory,
            root: root)
    }

    static func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GTDServicesTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: stateDirectory)
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: Reading the vault back

    /// Every file in the vault: path → text. The assertions of the acceptance list are about
    /// *files*, not about the snapshot the app happens to hold.
    func files() throws -> [String: String] {
        if let memory = fileSystem as? InMemoryFileSystem { return memory.snapshotOfFiles }
        guard let root else { return [:] }
        return try SampleVault.read(tree: root)
    }

    /// Everything except `GTD/Trash/`.
    ///
    /// Undoing the *creation* of a note cannot hard-delete it — `VaultFileSystem` has no delete
    /// at all (ARCHITECTURE §3) — so the inverse of "write this new file" is "move it to the
    /// trash". "Undo restores the vault byte for byte" is therefore a statement about the vault
    /// the app shows, plus one tombstone in the trash.
    func filesOutsideTheTrash() throws -> [String: String] {
        try files().filter { !$0.key.hasPrefix(VaultLayout.default.trash + "/") }
    }

    func text(_ path: String) throws -> String? {
        try fileSystem.readText(path)
    }

    /// What a cold start would see: a brand-new index over the same files. This is the snapshot
    /// that matters — the files are the truth, not what the backend remembers.
    func rescan() throws -> VaultSnapshot {
        var index = VaultIndex()
        try index.refresh(using: fileSystem)
        return index.snapshot(today: Fixtures.today)
    }
}
