import Foundation
import GTDFixtures
import GTDModel
import GTDServices
import GTDVault
import Testing

/// What `snapshots()` emits, and when.
///
/// The UI must never wait for a file system round trip after a command (that is the optimistic
/// emission), and it must end up on the snapshot the *files* say (that is the watcher echo).
@Suite("Snapshot emission")
struct SnapshotEmissionTests {

    @Test func aCommandEmitsItsSnapshotWithoutWaitingForTheStore() async throws {
        let store = PassiveStore(snapshot: Fixtures.sampleSnapshot)
        let backend = try await makeBackend(store)
        var snapshots = backend.snapshots().makeAsyncIterator()
        let first = try #require(await snapshots.next()).snapshot
        #expect(first.actions.contains { $0.title == "Write DAAD motivation letter" })

        _ = try await backend.perform(
            .createAction(ActionDraft(
                title: "Buy a desk lamp", status: .someday, what: "Order it.")))

        // The store never re-indexed and never published: this can only be the reduced snapshot.
        let optimistic = try #require(await snapshots.next()).snapshot
        #expect(optimistic.actions.contains { $0.title == "Buy a desk lamp" })
        #expect(await backend.currentSnapshot().actions.contains { $0.title == "Buy a desk lamp" })
        #expect(store.publishCalls == 0, "the store itself never pushed a snapshot")
    }

    @Test func aSnapshotFromTheStoreReplacesTheOptimisticOne() async throws {
        let store = PassiveStore(snapshot: Fixtures.sampleSnapshot)
        let backend = try await makeBackend(store)
        _ = try await backend.perform(
            .createAction(ActionDraft(
                title: "Buy a desk lamp", status: .someday, what: "Order it.")))

        // The watcher fires: another device added a note while we were working.
        var scanned = await backend.currentSnapshot()
        scanned.inbox.append(InboxItem(
            id: NoteID(path: "Inbox/from the phone.md"),
            body: "",
            created: Fixtures.date(Fixtures.today, 12, 0)))
        store.publish(scanned)

        try await eventually("the remote capture arrives") {
            await backend.currentSnapshot().inbox.contains { $0.title == "from the phone" }
        }
        #expect(await backend.currentSnapshot().actions.contains { $0.title == "Buy a desk lamp" })
    }

    /// A store that has not scanned yet publishes `VaultSnapshot.empty`. That placeholder must
    /// never replace a snapshot the backend already has — it would empty the whole UI.
    @Test func theEmptyPlaceholderNeverErasesAKnownSnapshot() async throws {
        let store = PassiveStore(snapshot: Fixtures.sampleSnapshot)
        let backend = try await makeBackend(store)
        store.publish(.empty)
        // Give the forwarding task a chance to act on it.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await backend.currentSnapshot().actions.isEmpty == false)
    }

    private func makeBackend(_ store: PassiveStore) async throws -> VaultBackend {
        let directory = TestVault.temporaryDirectory()
        let backend = VaultBackend(
            store: store,
            deviceID: "test-device",
            journal: UndoJournal(directory: directory),
            stateDirectory: directory,
            env: { Fixtures.reducerEnv(deviceID: "test-device") })
        try await backend.start()
        return backend
    }

    /// Polls until the condition holds — the store's snapshots reach the backend through a task,
    /// so there is nothing to await directly.
    ///
    /// The budget is generous on purpose: the suite runs its tests in parallel on a machine that
    /// may have nothing to spare, and a starved background task is not the behaviour under test.
    /// It returns as soon as the condition holds, so a passing run costs a millisecond.
    private func eventually(
        _ what: String, timeout: Duration = .seconds(10), _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("timed out waiting for \(what)")
    }
}

/// A `VaultStore` that applies operations but never re-indexes and never publishes on its own.
///
/// `FileVaultStore` re-indexes inside `commit`, which hides the optimistic path: a snapshot
/// would arrive either way. This one publishes only when a test says so, so "the UI sees the
/// command immediately" and "the store's value wins in the end" can be told apart.
final class PassiveStore: VaultStore, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String] = [:]
    private var latest: VaultSnapshot
    private var continuations: [UUID: AsyncStream<VaultSnapshot>.Continuation] = [:]
    private var publishCount = 0

    init(snapshot: VaultSnapshot) {
        latest = snapshot
        files = SampleVault.render(snapshot)
    }

    /// How often a *test* pushed a snapshot. The backend also subscribes to read the store's
    /// current value, and those subscriptions are not counted here.
    var publishCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return publishCount
    }

    func snapshots() -> AsyncStream<VaultSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = latest
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    func publish(_ snapshot: VaultSnapshot) {
        lock.lock()
        latest = snapshot
        publishCount += 1
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(snapshot) }
    }

    func read(path: String) async throws -> String? {
        withLock { files[path] }
    }

    func folderContents(_ folder: String) async throws -> [String]? {
        withLock {
            let prefix = folder.hasSuffix("/") ? folder : folder + "/"
            let inside = files.keys.filter { $0.hasPrefix(prefix) }.sorted()
            return inside.isEmpty ? nil : inside
        }
    }

    func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp] {
        try withLock { try apply(ops) }
    }

    /// `NSLock.lock()` may not be called from an async context, so every async entry point goes
    /// through this synchronous hatch.
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func apply(_ ops: [VaultFileOp]) throws -> [VaultFileOp] {
        var inverse: [VaultFileOp] = []
        for op in ops {
            switch op {
            case let .put(path, text):
                inverse.append(files[path].map { .put(path: path, text: $0) }
                    ?? .delete(path: path))
                files[path] = text
            case let .move(from, to):
                guard let text = files[from] else {
                    throw VaultError.ioFailed(path: from, reason: "no such file to move")
                }
                guard files[to] == nil else { throw VaultError.destinationExists(path: to) }
                files[to] = text
                files[from] = nil
                inverse.append(.move(from: to, to: from))
            case let .moveFolder(from, to):
                let prefix = from + "/"
                let inside = files.keys.filter { $0.hasPrefix(prefix) }
                guard !inside.isEmpty else {
                    throw VaultError.ioFailed(path: from, reason: "no such folder to move")
                }
                guard !files.keys.contains(where: { $0.hasPrefix(to + "/") || $0 == to }) else {
                    throw VaultError.destinationExists(path: to)
                }
                for path in inside {
                    files[to + "/" + String(path.dropFirst(prefix.count))] = files[path]
                    files[path] = nil
                }
                inverse.append(.moveFolder(from: to, to: from))
            case .createFolder:
                // This fake store models files only; an empty folder leaves no trace, and the
                // op has no inverse anyway (ARCHITECTURE §6).
                continue
            case let .delete(path):
                guard let text = files[path] else { continue }
                let trashed = VaultLayout.default.trashPath(for: NoteID(path: path)).path
                files[trashed] = text
                files[path] = nil
                inverse.append(.move(from: trashed, to: path))
            }
        }
        return inverse.reversed()
    }
}
