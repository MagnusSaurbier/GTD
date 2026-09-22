import Foundation

/// What a watcher knows about a change. `paths` is a **hint**, never a promise: it lets the store
/// re-stat those files instead of walking the vault, which is what makes an external write show
/// up at once. The files stay the truth — the index compares fingerprints for every hinted path,
/// falls back to a full refresh for anything it cannot place (a folder, an unknown parent), and
/// the polling safety net still compares the whole listing — so a wrong, missing or duplicated
/// hint costs a re-scan, never a wrong snapshot.
public enum VaultChange: Sendable, Equatable {
    case unknown
    /// Vault-relative paths of files that were written, created, moved or removed.
    case paths(Set<String>)

    public func merging(_ other: VaultChange) -> VaultChange {
        guard case let .paths(mine) = self, case let .paths(theirs) = other else { return .unknown }
        return .paths(mine.union(theirs))
    }
}

/// Tells the store "something under the vault root changed", and what, when it knows.
///
/// Implementations: `FSEventsVaultWatcher` (macOS — the only mechanism that sees a plain,
/// uncoordinated write such as Obsidian's or a script's), `PresenterVaultWatcher`
/// (`NSFilePresenter`, iOS/macOS — coordinated writes and iCloud's own) and
/// `PollingVaultWatcher` (mtime polling — ARCHITECTURE §7's fallback, and the only one that
/// exists on Linux).
public protocol VaultWatcher: Sendable {
    func start(onChange: @escaping @Sendable (VaultChange) -> Void)
    func stop()
}

extension VaultWatcher {
    /// For callers that only care *that* something changed.
    public func start(onChange: @escaping @Sendable () -> Void) {
        start { (_: VaultChange) in onChange() }
    }
}

/// A watcher that never fires — the default when the store is used as a one-shot scanner.
public struct NullVaultWatcher: VaultWatcher {
    public init() {}
    public func start(onChange: @escaping @Sendable (VaultChange) -> Void) {}
    public func stop() {}
}

/// Several watchers feeding one callback. They overlap on purpose — a duplicate costs a re-stat
/// of files whose fingerprints have not moved, and publishes nothing.
public struct CompositeVaultWatcher: VaultWatcher {
    private let watchers: [any VaultWatcher]

    public init(_ watchers: [any VaultWatcher]) { self.watchers = watchers }

    public func start(onChange: @escaping @Sendable (VaultChange) -> Void) {
        for watcher in watchers { watcher.start(onChange: onChange) }
    }

    public func stop() {
        for watcher in watchers { watcher.stop() }
    }
}

/// Polls the file listing and reports a change when any fingerprint, path or count differs.
///
/// The documented fallback (ARCHITECTURE §7: poll mtime every 5 s while foregrounded), and the
/// mechanism used on Linux. Cheap: one recursive listing per interval,
/// no file contents are read.
public final class PollingVaultWatcher: VaultWatcher, @unchecked Sendable {
    private let fileSystem: any VaultFileSystem
    private let interval: TimeInterval
    private let clock: any VaultClock
    private let lock = NSLock()
    private var worker: Task<Void, Never>?
    private var lastFingerprint: String?

    public init(
        fileSystem: any VaultFileSystem,
        interval: TimeInterval = 5,
        clock: any VaultClock = SystemVaultClock()
    ) {
        self.fileSystem = fileSystem
        self.interval = interval
        self.clock = clock
    }

    public func start(onChange: @escaping @Sendable (VaultChange) -> Void) {
        lock.lock()
        guard worker == nil else { lock.unlock(); return }
        lastFingerprint = currentFingerprint()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.clock.sleep(seconds: self.interval) } catch { return }
                guard !Task.isCancelled else { return }
                if self.pollDidChange() { onChange(.unknown) }
            }
        }
        worker = task
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        worker?.cancel()
        worker = nil
        lock.unlock()
    }

    /// Exposed so tests can drive the watcher deterministically instead of waiting for a tick.
    @discardableResult
    public func pollDidChange() -> Bool {
        let fingerprint = currentFingerprint()
        lock.lock(); defer { lock.unlock() }
        guard fingerprint != lastFingerprint else { return false }
        lastFingerprint = fingerprint
        return true
    }

    private func currentFingerprint() -> String {
        guard let files = try? fileSystem.listFiles() else { return "unreadable" }
        var hasher = Hasher()
        for file in files {
            hasher.combine(file.path)
            hasher.combine(file.fingerprint)
        }
        return "\(files.count):\(hasher.finalize())"
    }
}
