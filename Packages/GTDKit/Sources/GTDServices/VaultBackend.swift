import Foundation
import GTDAppCore
import GTDMarkdown
import GTDModel
import GTDVault

/// The production backend: every command goes `Reducer.reduce` → `SnapshotDiff` →
/// `VaultStore.commit` → undo journal, and the vault's markdown files stay the only truth.
///
/// ### One command, one transaction
/// A command never writes twice. The reducer's `extraOps` (trash, archive, knowledge and rename
/// moves) and the diff's content writes go into a single `commit`, which is all-or-nothing: a
/// refused cap or a failing write leaves the vault exactly as it was (`VaultError.rollbackFailed`
/// is the one exception, and it is shown, never retried — T15-1). That is why renaming an action
/// and rewriting the project steps that link to it cannot come apart.
///
/// ### Optimistic emission vs. the watcher echo
/// `snapshots()` is this backend's own stream. It carries two kinds of value:
/// * the **reduced** snapshot, published as soon as the commit succeeded, so the UI never waits
///   for a file system round trip, and
/// * the **scanned** snapshot the store publishes after re-indexing — the authoritative one,
///   with fresh modification dates and fresh `NotePassthrough`s.
/// The store's value wins whenever it is there: if it already arrived while we were committing,
/// the optimistic publish is skipped, and the next change replaces what we published. Logically
/// the two agree; the scan is only more precise about the fields that come from the file system
/// (`Action.modified`, `NotePassthrough`, `VaultIssue`s).
///
/// ### Housekeeping
/// `start()` (also run lazily before the first command) creates the folder skeleton
/// `VaultLayout` requires, scans, starts watching and runs `archiveCompleted` once per day —
/// the day of the last run is remembered next to the undo journal, outside the vault.
public actor VaultBackend: GTDBackend {

    private let store: any VaultStore
    private let deviceID: String
    private let journal: UndoJournal
    private let makeEnv: @Sendable () -> ReducerEnv
    private let housekeeping: HousekeepingState
    private let hub = BackendSnapshotHub()

    /// The last published state: the snapshot plus the renames of the command that produced
    /// it (`SnapshotUpdate`). The stream and `currentUpdate()` hand out the same value, so
    /// whichever of the two reaches the UI first carries the rename with it.
    private var latestUpdate: SnapshotUpdate = .empty
    private var latest: VaultSnapshot { latestUpdate.snapshot }
    /// The last snapshot taken *from the store*. Comparing against it answers the only question
    /// that matters after a commit: has the store re-read the vault yet?
    private var lastFromStore: VaultSnapshot?
    /// Counts published snapshots. A read of the store that started before the latest publish is
    /// dropped rather than applied — see `pullFromStore`.
    private var generation = 0
    private var forwarding: Task<Void, Never>?
    private var started = false

    /// The contract initialiser (ARCHITECTURE §4).
    public init(store: any VaultStore, deviceID: String) {
        self.init(store: store, deviceID: deviceID, journal: UndoJournal())
    }

    /// Full initialiser — tests pin the clock with `env` and the device-local state with
    /// `journal` / `stateDirectory`.
    public init(
        store: any VaultStore,
        deviceID: String,
        journal: UndoJournal,
        stateDirectory: URL? = UndoJournal.defaultDirectory,
        env: (@Sendable () -> ReducerEnv)? = nil
    ) {
        self.store = store
        self.deviceID = deviceID
        self.journal = journal
        self.makeEnv = env ?? { ReducerEnv.live(deviceID: deviceID) }
        self.housekeeping = HousekeepingState(directory: stateDirectory)
    }

    deinit { forwarding?.cancel() }

    // MARK: - GTDBackend

    nonisolated public func snapshots() -> AsyncStream<SnapshotUpdate> { hub.stream() }

    public func currentUpdate() -> SnapshotUpdate {
        latestUpdate
    }

    public func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        try await startIfNeeded()
        let env = makeEnv()
        let old = latest
        let reduction = try Reducer.reduce(old, command, env: env)

        let ops = try await resolveCollisions(
            try SnapshotDiff.ops(
                from: old,
                to: reduction.snapshot,
                extraOps: reduction.extraOps,
                timeZone: env.calendar.timeZone),
            layout: old.config.layout)

        guard !ops.isEmpty else {
            // Nothing to write (e.g. a status set to the value it already had). The reduced
            // snapshot is still published so the UI and `InMemoryBackend` behave alike.
            publish(reduction.snapshot, renames: reduction.renames)
            return reduction.prompts
        }

        let inverse = try await store.commit(ops)

        if Rules.isUndoable(command) {
            await journal.push(UndoJournal.Entry(
                label: UndoLabel.of(command, in: old),
                inverseOps: inverse,
                hashes: try await hashes(touchedBy: inverse)))
        }

        // `FileVaultStore` re-indexes inside `commit`, so its snapshot is both newer and more
        // precise than the reduced one (fresh modification dates and passthroughs) — take it
        // when it has moved since we last looked, and publish the reduced snapshot when it has
        // not, which is what makes the UI immediate. Asking the store here, instead of waiting
        // for its stream, is what keeps the two paths from racing.
        let scanned = await storeSnapshot()
        if let scanned, !scanned.isEmptyVault, scanned != lastFromStore {
            lastFromStore = scanned
            publish(scanned, renames: reduction.renames)
        } else {
            publish(reduction.snapshot, renames: reduction.renames)
        }
        return reduction.prompts
    }

    /// N6 — replays the inverse ops of the last undoable command, unless the vault moved on.
    public func undo() async throws {
        try await startIfNeeded()
        guard let entry = await journal.peek() else { throw ServiceError.nothingToUndo }
        try await checkUnchanged(entry.hashes)
        _ = try await store.commit(entry.inverseOps)
        await journal.pop()
        // `AppModel.undo()` reads `currentSnapshot()` the moment this returns, so the restored
        // vault has to be visible now rather than when the watcher gets round to it.
        if let scanned = await storeSnapshot(), !scanned.isEmptyVault, scanned != lastFromStore {
            lastFromStore = scanned
            publish(scanned)
        }
    }

    public func undoLabel() async -> String? {
        await journal.peek()?.label
    }

    // MARK: - Lifecycle

    /// Prepares the vault and runs the daily housekeeping. Idempotent; `perform` and `undo`
    /// call it themselves, so the app only needs it to warm up at launch.
    public func start() async throws {
        try await startIfNeeded()
    }

    /// Stops forwarding snapshots. The store is left alone — the app owns it.
    public func stop() {
        forwarding?.cancel()
        forwarding = nil
        hub.finish()
        started = false
    }

    private func startIfNeeded() async throws {
        guard !started else { return }
        started = true
        try await store.activate()
        // Synchronously, before anything else: a command must never reduce against the empty
        // placeholder a store publishes before its first scan.
        await pullFromStore()
        startForwarding()
        await runHousekeeping()
    }

    private func startForwarding() {
        guard forwarding == nil else { return }
        let stream = store.snapshots()
        forwarding = Task { [weak self] in
            // A subscription yields the store's current value first. `startIfNeeded` has just
            // taken that one; acting on it again would only risk re-publishing a value a command
            // running in between has already improved on.
            var isSubscribeValue = true
            for await _ in stream {
                guard !isSubscribeValue else {
                    isSubscribeValue = false
                    continue
                }
                await self?.pullFromStore()
            }
        }
    }

    /// The store's current snapshot, read without publishing it.
    ///
    /// A fresh subscription yields the store's latest value straight away, which is why the
    /// value the *stream* handed us is ignored everywhere: `AsyncStream` delivery is
    /// asynchronous, so a yielded snapshot can be older than what the store already knows.
    private func storeSnapshot() async -> VaultSnapshot? {
        var iterator = store.snapshots().makeAsyncIterator()
        return await iterator.next()
    }

    /// Publishes the store's current snapshot — unless a command published something while this
    /// read was in flight.
    ///
    /// Reading the store suspends, and a command can run in that gap. Its snapshot is by
    /// construction the newer one (it just committed and asked the store itself), so a read that
    /// started earlier is dropped instead of walking the app backwards.
    private func pullFromStore() async {
        let issuedAt = generation
        guard let snapshot = await storeSnapshot() else { return }
        guard generation == issuedAt else { return }
        // `.empty` is what a store publishes before its first scan; it must never erase a
        // snapshot we already have.
        guard !(snapshot.isEmptyVault && !latest.isEmptyVault) else { return }
        lastFromStore = snapshot
        publish(snapshot)
    }

    private func publish(_ snapshot: VaultSnapshot, renames: RenameMap = .empty) {
        generation += 1
        latestUpdate = SnapshotUpdate(snapshot: snapshot, renames: renames)
        hub.publish(latestUpdate)
    }

    /// A5 — archive done and trashed notes older than 30 days, at most once per day per device.
    ///
    /// The archive is not allowed to stop the user from working, so a failure is swallowed here
    /// rather than thrown out of `start()`. What it must **not** do is count as having happened:
    /// the day is recorded only on success, so a vault that was busy, read-only or half-synced is
    /// retried at the next launch instead of being skipped until tomorrow. The app shell runs the
    /// same command once a day through `AppModel.perform`, which is where a failure reaches the
    /// person (T15: a `rollbackFailed` is never silent).
    private func runHousekeeping() async {
        let today = makeEnv().today
        guard await housekeeping.shouldArchive(on: today) else { return }
        do {
            _ = try await perform(.archiveCompleted)
            await housekeeping.didArchive(on: today)
        } catch {
            lastHousekeepingError = error
        }
    }

    /// Why the last automatic archive did not run, for the settings screen and for tests.
    /// `nil` once one succeeds.
    public private(set) var lastHousekeepingError: (any Error)?

    // MARK: - Collisions

    /// `Rules.archiveCandidates` and the trash keep a note's own file name (T11), and
    /// `VaultStore` refuses to overwrite on a move (T15-1). Two notes archived in the same month,
    /// or a title that was trashed once before, would therefore fail the whole transaction — so
    /// the app-owned folders get a free name instead.
    ///
    /// Everywhere else a taken destination is the user's problem to solve, not ours to rename
    /// around: it becomes `GTDError.titleCollision`, which the UI already knows how to show.
    private func resolveCollisions(
        _ ops: [VaultFileOp], layout: VaultLayout
    ) async throws -> [VaultFileOp] {
        var resolved: [VaultFileOp] = []
        var taken = Set<String>()
        for op in ops {
            guard case let .move(from, to) = op else {
                resolved.append(op)
                continue
            }
            if try await exists(to) || taken.contains(to) {
                let isAppOwned = to.hasPrefix(layout.archive + "/") || to.hasPrefix(layout.trash + "/")
                guard isAppOwned else {
                    throw GTDError.titleCollision(NoteID(path: to).title)
                }
                let free = try await freeName(near: to, taken: taken)
                taken.insert(free)
                resolved.append(.move(from: from, to: free))
                continue
            }
            taken.insert(to)
            resolved.append(op)
        }
        return resolved
    }

    private func freeName(near path: String, taken: Set<String>) async throws -> String {
        let id = NoteID(path: path)
        let folder = id.folder
        let name = id.title
        let ext = path.hasSuffix(".md") ? ".md" : ""
        for suffix in 2...999 {
            let candidate = folder.isEmpty
                ? "\(name) \(suffix)\(ext)"
                : "\(folder)/\(name) \(suffix)\(ext)"
            if try await !exists(candidate), !taken.contains(candidate) { return candidate }
        }
        let unique = folder.isEmpty
            ? "\(name) \(UUID().uuidString)\(ext)"
            : "\(folder)/\(name) \(UUID().uuidString)\(ext)"
        return unique
    }

    private func exists(_ path: String) async throws -> Bool {
        do {
            return try await store.read(path: path) != nil
        } catch {
            // An evicted iCloud item exists but cannot be read — treat it as taken (N3 §7.4).
            return true
        }
    }

    // MARK: - Undo safety

    /// The files an undo would overwrite or move, as they look right now.
    private func hashes(touchedBy ops: [VaultFileOp]) async throws -> [String: String] {
        var hashes: [String: String] = [:]
        for path in SnapshotDiff.ownedPaths(in: ops).sorted() {
            hashes[path] = ContentHash.of(try? await store.read(path: path))
        }
        return hashes
    }

    /// N3 — refuses the undo when any of those files changed since. Better a clear refusal than
    /// a silently lost edit from another device.
    private func checkUnchanged(_ hashes: [String: String]) async throws {
        for path in hashes.keys.sorted() {
            let now = ContentHash.of(try? await store.read(path: path))
            guard now == hashes[path] else { throw ServiceError.undoStale(path: path) }
        }
    }
}

// MARK: - Snapshot fan-out

/// Fans this backend's snapshots out to every `snapshots()` subscriber. It lives outside the
/// actor because `GTDBackend.snapshots()` is synchronous and must work from any isolation
/// domain; every access is under the lock, which makes `@unchecked Sendable` sound.
final class BackendSnapshotHub: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: SnapshotUpdate = .empty
    private var continuations: [UUID: AsyncStream<SnapshotUpdate>.Continuation] = [:]

    func stream() -> AsyncStream<SnapshotUpdate> {
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

    func publish(_ update: SnapshotUpdate) {
        lock.lock()
        latest = update
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(update) }
    }

    func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }
}

extension VaultSnapshot {
    /// True for the placeholder snapshot a store publishes before its first scan.
    var isEmptyVault: Bool {
        inbox.isEmpty && actions.isEmpty && areas.isEmpty && projects.isEmpty
            && routines.isEmpty && routineLog.isEmpty && lastReview == nil && issues.isEmpty
    }
}
