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
/// ### The UI never waits for a file
/// `perform` returns as soon as the rules have spoken: the reduced snapshot is published and the
/// file operations join a serial queue (`drain`). A coordinated write into an iCloud folder can
/// take seconds while the sync daemon is busy, and the re-index after it walks the whole vault —
/// none of that is on the path of a tap any more. "Written" means the **local** file is written;
/// the upload is iCloud's business and nothing here waits for it. A write that is refused takes
/// the queue behind it down with it, the vault is re-read and published, and the refusal goes
/// out on `writeFailures()` — `AppModel` shows it. `WritePolicy.awaited` keeps the old
/// behaviour (the write's error is thrown from `perform`) for tests and tools that read the
/// files straight after a command.
///
/// ### Optimistic emission vs. the watcher echo
/// `snapshots()` is this backend's own stream. It carries two kinds of value:
/// * the **reduced** snapshot, published before anything is written, so the UI never waits
///   for a file system round trip, and
/// * the **scanned** snapshot the store publishes after re-indexing — the authoritative one,
///   with fresh modification dates and fresh `NotePassthrough`s.
/// The store's value wins whenever the queue is empty: `drain` takes it after the last write,
/// and the watcher's events are ignored while writes are still waiting. Logically
/// the two agree; the scan is only more precise about the fields that come from the file system
/// (`Action.modified`, `NotePassthrough`, `VaultIssue`s).
///
/// ### The stale-write guard (N3)
/// A command is reduced on a snapshot, and the snapshot can be behind the vault: a sync landing,
/// Obsidian, another device. Before `commit`, every file the command would overwrite or move
/// away from is read and compared with what the base snapshot says it holds
/// (`SnapshotDiff.expectedContents`); a mismatch is `ServiceError.staleWrite`, and the queue is
/// abandoned like any other refusal — re-read, published, reported. It is a refusal, never a
/// merge (ARCHITECTURE §6, 2026-09-24). Staleness is about the *files*, not the snapshot's age:
/// a week offline commits fine as long as the touched notes did not change. Re-scan first,
/// refuse second: `perform` pulls the store's newest snapshot before reducing, so a change the
/// store has indexed but the backend has not received yet never turns into a refusal.
///
/// ### Housekeeping
/// `start()` (also run lazily before the first command) creates the folder skeleton
/// `VaultLayout` requires if it is missing, scans and starts watching. `archiveCompleted` runs
/// once per day **behind the first write the person causes** — never at launch, never on a
/// timer — and the day of the last run is remembered next to the undo journal, outside the
/// vault. (`WritePolicy.awaited` archives inside `start()`, which is what the file-asserting
/// suites expect.)
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

    private let writes: WritePolicy
    private let failures = WriteFailureHub()
    /// Commands whose snapshot is published and whose files are not written yet, oldest first.
    private var pending: [PendingWrite] = []
    private var drainTask: Task<Void, Never>?
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []
    /// Counts refused writes, so `undo()` can tell that one happened while it waited.
    private var failureCount = 0

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
        env: (@Sendable () -> ReducerEnv)? = nil,
        writes: WritePolicy = .queued
    ) {
        self.writes = writes
        self.store = store
        self.deviceID = deviceID
        self.journal = journal
        self.makeEnv = env ?? { ReducerEnv.live(deviceID: deviceID) }
        self.housekeeping = HousekeepingState(directory: stateDirectory)
    }

    deinit { forwarding?.cancel() }

    // MARK: - GTDBackend

    nonisolated public func snapshots() -> AsyncStream<SnapshotUpdate> { hub.stream() }

    nonisolated public func writeFailures() -> AsyncStream<WriteFailure> { failures.stream() }

    public func currentUpdate() -> SnapshotUpdate {
        latestUpdate
    }

    public func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        try await perform(command, awaitingWrite: writes == .awaited)
    }

    /// The command up to the point where the rules have spoken, then the queue.
    ///
    /// Nothing between reading `latest` and enqueueing suspends, so two commands can never
    /// reduce against the same base: the second one always sees the first one's snapshot.
    private func perform(
        _ command: GTDCommand, awaitingWrite: Bool, housekeepingDay: Day? = nil
    ) async throws -> [AppPrompt] {
        try await startIfNeeded()
        // Re-scan first, refuse second: reduce on the newest snapshot the store has. A no-op in
        // the steady state (`drain` and the forwarding task already pulled it) and while writes
        // are queued (the store cannot know them yet, README §5).
        await pullFromStore(onlyIfMoved: true)
        let env = makeEnv()
        let old = latest
        let reduction = try Reducer.reduce(old, command, env: env)

        let ops = try SnapshotDiff.ops(
            from: old,
            to: reduction.snapshot,
            extraOps: reduction.extraOps,
            filedNotes: reduction.filedNotes,
            timeZone: env.calendar.timeZone)

        // The reduced snapshot is what the person sees from here on — the files follow.
        publish(reduction.snapshot, renames: reduction.renames)

        guard !ops.isEmpty else {
            // Nothing to write (e.g. a status set to the value it already had). The reduced
            // snapshot is still published so the UI and `InMemoryBackend` behave alike.
            if let housekeepingDay { await housekeeping.didArchive(on: housekeepingDay) }
            return reduction.prompts
        }

        let write = PendingWrite(
            ops: ops,
            expected: SnapshotDiff.expectedContents(
                before: ops, in: old, timeZone: env.calendar.timeZone),
            layout: old.config.layout,
            label: UndoLabel.of(command, in: old),
            isUndoable: Rules.isUndoable(command),
            renames: reduction.renames,
            housekeepingDay: housekeepingDay)
        if awaitingWrite {
            try await withCheckedThrowingContinuation { waiter in
                enqueue(write, waiter: waiter)
            }
        } else {
            enqueue(write, waiter: nil)
        }
        return reduction.prompts
    }

    // MARK: - The write queue

    /// One command's file operations, waiting for their turn.
    private struct PendingWrite {
        var ops: [VaultFileOp]
        /// What each file the ops touch must still hold when their turn comes (N3), path →
        /// `ContentHash`.
        var expected: [String: String]
        var layout: VaultLayout
        var label: String
        var isUndoable: Bool
        var renames: RenameMap
        /// Set on the daily archive: the day to record once its files really moved (A5).
        var housekeepingDay: Day?
        /// Set when somebody awaits this very write (`WritePolicy.awaited`, housekeeping): the
        /// failure is thrown to them instead of being announced on `writeFailures()`.
        var waiter: CheckedContinuation<Void, any Error>?
    }

    private func enqueue(_ write: PendingWrite, waiter: CheckedContinuation<Void, any Error>?) {
        var write = write
        write.waiter = waiter
        pending.append(write)
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in await self?.drain() }
    }

    /// Commits the queue front to back, then takes the store's scanned snapshot.
    ///
    /// Only this task removes from `pending`, and only it starts a commit, so writes reach the
    /// vault one at a time and in the order the commands ran.
    private func drain() async {
        repeat {
            while let write = pending.first {
                do {
                    try await commit(write)
                    pending.removeFirst()
                    write.waiter?.resume()
                    if let day = write.housekeepingDay {
                        await housekeeping.didArchive(on: day)
                        lastHousekeepingError = nil
                    } else {
                        await queueHousekeepingIfDue()
                    }
                } catch {
                    await abandonQueue(after: error)
                }
            }
            // Optimistic then authoritative (README §5): the scan has the fresh modification
            // dates and passthroughs. `pullFromStore` drops itself if a command ran meanwhile —
            // then the loop goes round again and the next idle moment reconciles. Only a
            // snapshot that **moved** counts: a store whose re-index failed (or that does not
            // re-index on commit) still holds the state from before these writes, and
            // publishing that would take them back off the screen although they are on disk.
            await pullFromStore(onlyIfMoved: true)
        } while !pending.isEmpty
        drainTask = nil
        let waiters = flushWaiters
        flushWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// The file-system half of a command: collisions, the stale-write guard, the one
    /// transaction, the undo journal. Collisions go first: a taken destination in a folder the
    /// index does not read (`Knowledge/`) is a `titleCollision` the person resolves, not a stale
    /// snapshot.
    private func commit(_ write: PendingWrite) async throws {
        let ops = try await resolveCollisions(write.ops, layout: write.layout)
        try await refuseIfStale(write.expected)
        let inverse = try await store.commit(ops)
        if write.isUndoable {
            await journal.push(UndoJournal.Entry(
                label: write.label,
                inverseOps: inverse,
                hashes: try await hashes(touchedBy: inverse)))
        }
    }

    /// A write was refused. The snapshot the person is looking at promised it — and every write
    /// queued behind it was reduced on top of that promise — so all of them are dropped, the
    /// vault is read again and **that** is published: the UI goes back to what the files say.
    /// Then the person is told (`writeFailures()`), or whoever awaited the write is.
    private func abandonQueue(after error: any Error) async {
        failureCount += 1
        var dropped: [PendingWrite] = []
        var truth: VaultSnapshot?
        repeat {
            // A command that slips in while the vault is being re-read was reduced on the same
            // broken promise; it goes too.
            dropped += pending
            pending.removeAll()
            // A failed commit does not re-index, and after `rollbackFailed` the files may be in
            // a mixed state — scan rather than trust the last snapshot.
            try? await store.activate()
            truth = await storeSnapshot()
        } while !pending.isEmpty

        if let truth, !(truth.isEmptyVault && !latest.isEmptyVault) {
            lastFromStore = truth
            let undone = dropped.reversed().reduce(RenameMap.empty) {
                $0.merging($1.renames.inverted)
            }
            publish(truth, renames: undone)
        }

        guard let first = dropped.first else { return }
        if first.housekeepingDay != nil { lastHousekeepingError = error }
        if let waiter = first.waiter {
            waiter.resume(throwing: error)
        } else {
            failures.publish(WriteFailure(
                label: first.label, reason: error, discarded: dropped.count - 1))
        }
        for later in dropped.dropFirst() {
            later.waiter?.resume(throwing: ServiceError.writeDiscarded)
        }
    }

    /// Returns once every queued write has reached the vault (or was refused). The app calls it
    /// before it lets go of the vault and when it is sent to the background.
    public func flush() async {
        guard drainTask != nil else { return }
        await withCheckedContinuation { flushWaiters.append($0) }
    }

    /// N6 — replays the inverse ops of the last undoable command, unless the vault moved on.
    ///
    /// The journal entry of a command exists only once its write landed, so undo waits for the
    /// queue. If a write was refused in the meantime, the thing the person meant to undo is
    /// already gone — undoing the entry *below* it would revert something they did not ask for.
    public func undo() async throws {
        try await startIfNeeded()
        let failuresBefore = failureCount
        await flush()
        guard failureCount == failuresBefore else { throw ServiceError.writeDiscarded }
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

    /// A queued command is undoable the moment it ran, so its label is offered before its
    /// journal entry exists.
    public func undoLabel() async -> String? {
        if let queued = pending.last(where: \.isUndoable) { return queued.label }
        return await journal.peek()?.label
    }

    // MARK: - Lifecycle

    /// Prepares the vault and runs the daily housekeeping. Idempotent; `perform` and `undo`
    /// call it themselves, so the app only needs it to warm up at launch.
    public func start() async throws {
        try await startIfNeeded()
    }

    /// Lets the queued writes land, then stops forwarding snapshots. The store is left alone —
    /// the app owns it.
    public func stop() async {
        await flush()
        failures.finish()
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
        // Queued policy: opening the vault writes **nothing**. The archive rides behind the
        // first change the person makes that day (`queueHousekeepingIfDue`).
        if writes == .awaited { await runHousekeeping() }
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
    ///
    /// And never while writes are queued: the store cannot know about them yet, so its snapshot
    /// — the watcher's echo of write 1 while write 2 waits — would take back what the person
    /// just did. `drain` pulls once the queue is empty.
    private func pullFromStore(onlyIfMoved: Bool = false) async {
        guard pending.isEmpty else { return }
        let issuedAt = generation
        guard let snapshot = await storeSnapshot() else { return }
        guard generation == issuedAt, pending.isEmpty else { return }
        guard !(onlyIfMoved && snapshot == lastFromStore) else { return }
        // Every publish re-renders the app; one that says what the app already shows is noise.
        guard snapshot != latest else {
            lastFromStore = snapshot
            return
        }
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
    /// person — a `rollbackFailed` is never silent.
    private func runHousekeeping() async {
        let today = makeEnv().today
        guard await housekeeping.shouldArchive(on: today) else { return }
        do {
            _ = try await perform(.archiveCompleted, awaitingWrite: true)
            await housekeeping.didArchive(on: today)
        } catch {
            lastHousekeepingError = error
        }
    }

    /// The production path of A5. The vault is only ever written when the person acts on an item,
    /// so the daily archive does not get a write of its own at launch or on a timer: it joins the
    /// queue right behind the first write of the day that landed — the queue is writing anyway,
    /// and nobody waits for either. A Mac that stays open over midnight is covered by the same
    /// check. A refused archive is reported like any refused write; the day is not recorded, so
    /// the next launch tries again.
    private func queueHousekeepingIfDue() async {
        guard writes == .queued else { return }
        let today = makeEnv().today
        guard housekeepingCheckedOn != today else { return }
        housekeepingCheckedOn = today
        guard await housekeeping.shouldArchive(on: today) else { return }
        do {
            _ = try await perform(.archiveCompleted, awaitingWrite: false, housekeepingDay: today)
        } catch {
            lastHousekeepingError = error
        }
    }

    /// The day `queueHousekeepingIfDue` last looked, so it asks once per day and process.
    private var housekeepingCheckedOn: Day?

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
    /// Internal rather than private so `FolderMoveTests` can pin the policy for a folder move —
    /// `removeList` and a project's area change (R-5/R-7) are the commands that emit one.
    func resolveCollisions(
        _ ops: [VaultFileOp], layout: VaultLayout
    ) async throws -> [VaultFileOp] {
        var resolved: [VaultFileOp] = []
        var taken = Set<String>()
        for op in ops {
            switch op {
            case let .move(from, to):
                resolved.append(.move(
                    from: from,
                    to: try await freeDestination(to, isFolder: false, layout: layout, taken: &taken)))
            case let .moveFolder(from, to):
                // R-5: removing a list is a folder move into `GTD/Trash/`, and the same list may
                // be removed, re-created and removed again. App-owned folders take a free name;
                // anywhere else — a list renamed onto a name that exists, a project moved into an
                // area that already has one — the user resolves it.
                resolved.append(.moveFolder(
                    from: from,
                    to: try await freeDestination(to, isFolder: true, layout: layout, taken: &taken)))
            case .put, .delete, .createFolder:
                // `createFolder` is idempotent and creates nothing that could collide: a list
                // whose folder is already there is simply already there.
                resolved.append(op)
            }
        }
        return resolved
    }

    /// `to` itself when it is free; a free name beside it when it is taken and lives in an
    /// app-owned folder; `GTDError.titleCollision` otherwise.
    private func freeDestination(
        _ to: String, isFolder: Bool, layout: VaultLayout, taken: inout Set<String>
    ) async throws -> String {
        guard try await isOccupied(to, isFolder: isFolder) || taken.contains(to) else {
            taken.insert(to)
            return to
        }
        let isAppOwned = to.hasPrefix(layout.archive + "/") || to.hasPrefix(layout.trash + "/")
        guard isAppOwned else { throw GTDError.titleCollision(NoteID(path: to).title) }
        let free = try await freeName(near: to, isFolder: isFolder, taken: taken)
        taken.insert(free)
        return free
    }

    private func freeName(
        near path: String, isFolder: Bool, taken: Set<String>
    ) async throws -> String {
        let id = NoteID(path: path)
        let folder = id.folder
        let name = id.title
        let ext = path.hasSuffix(".md") ? ".md" : ""
        for suffix in 2...999 {
            let candidate = folder.isEmpty
                ? "\(name) \(suffix)\(ext)"
                : "\(folder)/\(name) \(suffix)\(ext)"
            if try await !isOccupied(candidate, isFolder: isFolder), !taken.contains(candidate) {
                return candidate
            }
        }
        let unique = folder.isEmpty
            ? "\(name) \(UUID().uuidString)\(ext)"
            : "\(folder)/\(name) \(UUID().uuidString)\(ext)"
        return unique
    }

    /// Is something already at `path`? A folder is invisible to `read(path:)`, so a folder
    /// destination asks the store for the folder as well (T02-1).
    private func isOccupied(_ path: String, isFolder: Bool) async throws -> Bool {
        if try await exists(path) { return true }
        guard isFolder else { return false }
        return try await store.folderContents(path) != nil
    }

    private func exists(_ path: String) async throws -> Bool {
        do {
            return try await store.read(path: path) != nil
        } catch {
            // An evicted iCloud item exists but cannot be read — treat it as taken (N3 §7.4).
            return true
        }
    }

    // MARK: - Stale-write guard

    /// N3 — refuses the write when a file it would overwrite or move no longer holds what the
    /// snapshot it was reduced on says. Reads go straight to the files, not the index, so the
    /// answer is as fresh as the disk. A file that cannot be read (evicted, N3 §7.4) refuses
    /// with the store's own error rather than a misleading "changed elsewhere".
    private func refuseIfStale(_ expected: [String: String]) async throws {
        for path in expected.keys.sorted() {
            let now = ContentHash.of(try await store.read(path: path))
            guard now == expected[path] else { throw ServiceError.staleWrite(path: path) }
        }
    }

    // MARK: - Undo safety

    /// The files an undo would overwrite or move, as they look right now.
    ///
    /// `ops` are the **inverse** ops, so a `.moveFolder` names the folder where it sits after the
    /// commit. Every file below it travels back with the undo, so every one of them is hashed —
    /// otherwise undoing a list rename or an area change would carry an edit someone made inside
    /// the folder in the meantime back to the old path, unnoticed (N3 §7.6).
    private func hashes(touchedBy ops: [VaultFileOp]) async throws -> [String: String] {
        var paths = SnapshotDiff.ownedPaths(in: ops)
        for move in SnapshotDiff.foldersMoved(in: ops) {
            paths.formUnion(try await store.folderContents(move.from) ?? [])
        }
        var hashes: [String: String] = [:]
        for path in paths.sorted() {
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

/// Whether `VaultBackend.perform` returns before or after its files are written.
public enum WritePolicy: Sendable {
    /// Production: publish, queue the write, return. A refusal arrives on `writeFailures()`.
    case queued
    /// `perform` returns once the write landed and throws its error.
    case awaited
}

/// Fans refused writes out to `writeFailures()` subscribers. Unlike a snapshot a failure has no
/// "current value": a subscriber gets the ones that happen while it listens.
final class WriteFailureHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<WriteFailure>.Continuation] = [:]

    func stream() -> AsyncStream<WriteFailure> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    func publish(_ failure: WriteFailure) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(failure) }
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
