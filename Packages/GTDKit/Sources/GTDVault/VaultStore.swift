import Foundation
import GTDModel

/// The only module that touches the file system (ARCHITECTURE §2).
///
/// `commit` returns the **inverse** ops, already ordered for undo: passing them straight back
/// into `commit` restores the previous state (T16's undo journal does exactly that).
public protocol VaultStore: Sendable {
    func snapshots() -> AsyncStream<VaultSnapshot>
    func read(path: String) async throws -> String?
    /// Applies the operations in order and returns the inverse ops, for the undo journal.
    /// A `.delete` moves the file into `GTD/Trash/` — the app never hard-deletes (N3).
    func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp]

    /// Vault-relative paths of every file below `folder`, recursively, or `nil` when there is no
    /// such folder.
    ///
    /// `GTDServices` needs it for the two questions a `.moveFolder` raises and that no other op
    /// does (R-5, contract change T02-1): *is that destination free?* — a folder is invisible to
    /// `read(path:)` — and *which files would an undo of this move carry back?*, which is what
    /// the undo journal hashes so a folder move goes stale when anything inside it changed.
    func folderContents(_ folder: String) async throws -> [String]?

    /// Makes the store usable: creates the folders the layout requires, scans once and starts
    /// watching for changes. Idempotent — callers may call it before every command.
    ///
    /// Added by T16 (contract change T16-1) so `GTDServices` can do its housekeeping — "the
    /// folder skeleton exists" — without reaching past `VaultStore` to a file system, which
    /// would break "only `GTDVault` touches the file system" (ARCHITECTURE §2).
    /// A store that needs no preparation inherits the no-op default below.
    func activate() async throws
}

extension VaultStore {
    public func activate() async throws {}
}

public enum VaultError: Error, Equatable {
    case notImplemented(String)
    case noVaultSelected
    case bookmarkStale
    /// An evicted iCloud item; the download has been requested (N3 §7.4).
    case notDownloaded(path: String)
    case ioFailed(path: String, reason: String)
    /// A move would have overwritten an existing file. The store never overwrites on a move —
    /// the caller picks another name.
    case destinationExists(path: String)
    /// A commit failed *and* undoing what it had already applied failed too. The vault is in a
    /// mixed state; both reasons are carried so the user can be told the truth.
    case rollbackFailed(reason: String, rollbackReason: String)
}

/// Fans one snapshot out to every `snapshots()` subscriber. `snapshots()` is synchronous in the
/// contract, so the state is held under a lock rather than in the actor.
final class SnapshotHub: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: VaultSnapshot
    private var continuations: [UUID: AsyncStream<VaultSnapshot>.Continuation] = [:]

    init(initial: VaultSnapshot) { latest = initial }

    var current: VaultSnapshot {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func stream() -> AsyncStream<VaultSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = latest
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    func publish(_ snapshot: VaultSnapshot) {
        lock.lock()
        latest = snapshot
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(snapshot) }
    }

    func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }
}

/// Scans the vault, watches it for changes and commits file operations.
///
/// Everything happens on this actor, so a scan never blocks the main thread and a commit can
/// never interleave with a re-index. The pieces it drives — `VaultFileSystem`, `VaultIndex`,
/// `VaultTransaction`, `VaultWatcher`, `ChangeDebouncer` — are all injectable and individually
/// testable.
public actor FileVaultStore: VaultStore {
    private let fileSystem: any VaultFileSystem
    private let layout: VaultLayout
    private let today: @Sendable () -> Day
    private let hub: SnapshotHub
    private var index: VaultIndex
    private var watcher: (any VaultWatcher)?
    private var debouncer: ChangeDebouncer?
    private let debounce: DebounceState
    private let clock: any VaultClock
    private var isWatching = false
    private var hasPublished = false
    private var publishedDay: Day?
    /// What the watchers reported since the last re-index; `nil` when nothing is pending.
    private var pendingChange: VaultChange?

    /// The contract initialiser (ARCHITECTURE §4): a vault at `root`, the platform's coordinated
    /// file system and change watcher, `GTDMarkdown.NoteCodec` for parsing.
    public init(root: URL, layout: VaultLayout = .default) {
        self.init(fileSystem: VaultPlatform.makeFileSystem(root: root), layout: layout)
    }

    /// Full initialiser — what the tests use.
    public init(
        fileSystem: any VaultFileSystem,
        layout: VaultLayout = .default,
        parser: any VaultNoteParser = NoteCodecParser(),
        watcher: (any VaultWatcher)? = nil,
        debounce: DebounceState = .default,
        clock: any VaultClock = SystemVaultClock(),
        today: @escaping @Sendable () -> Day = Day.today
    ) {
        self.fileSystem = fileSystem
        self.layout = layout
        self.today = today
        self.clock = clock
        self.debounce = debounce
        self.watcher = watcher
        self.index = VaultIndex(layout: layout, parser: parser)
        self.hub = SnapshotHub(initial: .empty)
    }

    // MARK: VaultStore

    /// The current snapshot first, then one per change. Empty until the first `scan()`.
    nonisolated public func snapshots() -> AsyncStream<VaultSnapshot> { hub.stream() }

    public func read(path: String) async throws -> String? {
        try fileSystem.readText(path)
    }

    /// T02-1. Reads the tree rather than the index: a folder move takes *every* file with it,
    /// including the ones the index ignores (`Knowledge/`, attachments, a `Done/` log).
    public func folderContents(_ folder: String) async throws -> [String]? {
        guard fileSystem.folderExists(folder) else { return nil }
        let prefix = VaultPath.normalize(folder) + "/"
        return try fileSystem.listFiles().map(\.path).filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Applies `ops`, re-indexes, publishes, and returns the inverse ops in undo order.
    ///
    /// The re-index happens after a successful commit only: a failed commit has been rolled back,
    /// so the last published snapshot is still the truth.
    ///
    /// The store knows exactly which files it just touched, so it re-reads those instead of
    /// walking the vault (the inverse ops name the trash paths a `.delete` picked). A folder op
    /// falls back to the walk inside `refresh(hint:)`.
    public func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp] {
        guard !ops.isEmpty else { return [] }
        let transaction = VaultTransaction(fileSystem: fileSystem, layout: layout)
        let inverse = try transaction.commit(ops)
        _ = try? refresh(hint: Self.touched(by: ops + inverse))
        return inverse
    }

    private static func touched(by ops: [VaultFileOp]) -> VaultChange {
        var paths: Set<String> = []
        for op in ops {
            switch op {
            case let .put(path, _), let .delete(path): paths.insert(path)
            case let .move(from, to): paths.formUnion([from, to])
            case .moveFolder, .createFolder: return .unknown
            }
        }
        return .paths(paths)
    }

    // MARK: Scanning

    /// Creates the folder skeleton, scans and starts watching (T16-1). Idempotent: after the
    /// first call it only refreshes the index.
    public func activate() async throws {
        for folder in layout.requiredFolders where !fileSystem.exists(folder) {
            try fileSystem.createFolder(folder)
        }
        try scan()
        startWatching()
    }

    /// Indexes the whole vault and publishes the snapshot. Safe to call repeatedly — after the
    /// first call it is the incremental path.
    @discardableResult
    public func scan() throws -> VaultSnapshot {
        try refresh()
    }

    public var currentSnapshot: VaultSnapshot { hub.current }

    /// The `VaultIssue`s of the last scan, for the settings screen.
    public var issues: [VaultIssue] { hub.current.issues }

    /// `hint` = `.paths` re-reads only those files when the index can answer that honestly
    /// (`VaultIndex.refresh(paths:using:)`), and walks the vault otherwise.
    ///
    /// A refresh that found nothing new publishes nothing: every published snapshot re-renders
    /// the app, and the watchers overlap on purpose (our own writes echo, the poll re-checks).
    @discardableResult
    private func refresh(hint: VaultChange = .unknown) throws -> VaultSnapshot {
        var report: VaultIndex.RefreshReport?
        if case let .paths(paths) = hint {
            report = try index.refresh(paths: paths, using: fileSystem)
        }
        let resolved = try report ?? index.refresh(using: fileSystem)
        let day = today()
        guard resolved.changed || !hasPublished || day != publishedDay else { return hub.current }
        let snapshot = index.snapshot(today: day)
        hasPublished = true
        publishedDay = day
        hub.publish(snapshot)
        return snapshot
    }

    // MARK: Watching

    /// Starts the change watcher. Every burst of file events is debounced (50 ms of quiet, at
    /// most 500 ms — `DebounceState`) into one re-index, so a sync landing 200 files produces a
    /// few snapshots, not 200, while a single external write is on screen at once.
    public func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        let watcher = self.watcher ?? VaultPlatform.makeWatcher(fileSystem: fileSystem, clock: clock)
        self.watcher = watcher

        let debouncer = ChangeDebouncer(state: debounce, clock: clock) { [weak self] in
            await self?.handleExternalChange()
        }
        self.debouncer = debouncer
        watcher.start { [weak self] (change: VaultChange) in
            Task {
                await self?.note(change)
                await debouncer.signal()
            }
        }
    }

    public func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        watcher?.stop()
        let debouncer = self.debouncer
        self.debouncer = nil
        Task { await debouncer?.cancel() }
    }

    /// Ends every `snapshots()` stream. The app calls this on teardown.
    public func close() {
        stopWatching()
        hub.finish()
    }

    private func note(_ change: VaultChange) {
        pendingChange = pendingChange?.merging(change) ?? change
    }

    private func handleExternalChange() {
        let change = pendingChange ?? .unknown
        pendingChange = nil
        _ = try? refresh(hint: change)
    }

    /// For tests: pretends the watcher fired and waits for the debounced re-index.
    public func simulateChangeForTesting() async {
        guard let debouncer else {
            _ = try? refresh()
            return
        }
        await debouncer.signal()
        await debouncer.drainForTesting()
    }
}
