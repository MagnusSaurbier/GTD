import Foundation

/// Tells the store "something under the vault root changed".
///
/// It reports *that* something changed, never *what*: the index decides what to re-read from the
/// file listing, so a missed or duplicated event can never corrupt the snapshot — at worst the
/// app re-scans once too often or is one poll interval late.
///
/// Implementations: `PresenterVaultWatcher` (`NSFilePresenter`, iOS/macOS) and
/// `PollingVaultWatcher` (mtime polling — the fallback the brief asks for, and the only one that
/// exists on Linux).
public protocol VaultWatcher: Sendable {
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// A watcher that never fires — the default when the store is used as a one-shot scanner.
public struct NullVaultWatcher: VaultWatcher {
    public init() {}
    public func start(onChange: @escaping @Sendable () -> Void) {}
    public func stop() {}
}

/// Polls the file listing and reports a change when any fingerprint, path or count differs.
///
/// The documented fallback (ARCHITECTURE §7, T15 brief: "poll mtime every 5 s while
/// foregrounded"), and the mechanism used on Linux. Cheap: one recursive listing per interval,
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

    public func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        guard worker == nil else { lock.unlock(); return }
        lastFingerprint = currentFingerprint()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.clock.sleep(seconds: self.interval) } catch { return }
                guard !Task.isCancelled else { return }
                if self.pollDidChange() { onChange() }
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
