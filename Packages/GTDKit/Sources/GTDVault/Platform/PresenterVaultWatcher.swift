#if os(iOS) || os(macOS)
import Foundation

/// `NSFilePresenter` on the vault root — the mechanism ARCHITECTURE §7 and the T15 brief name.
///
/// A presenter registered on a *directory* is told about changes to anything below it, including
/// the ones iCloud makes when a sibling device syncs, which is exactly what the store needs.
/// Debouncing happens one level up, in `FileVaultStore`'s `ChangeDebouncer`, so this type only
/// forwards "something changed".
///
/// A polling watcher runs alongside as a safety net: presenter callbacks are known to be missed
/// when the app is suspended, and a missed callback would leave the app showing a stale vault
/// until the next launch. Both feed the same debouncer, so a duplicate costs one re-index.
///
/// **Compiled blind** — see `GTDVault/README.md`.
public final class PresenterVaultWatcher: VaultWatcher, @unchecked Sendable {
    private let root: URL
    private let fallback: PollingVaultWatcher
    private let lock = NSLock()
    private var presenter: Presenter?

    public init(root: URL, fallback: PollingVaultWatcher) {
        self.root = root.standardizedFileURL
        self.fallback = fallback
    }

    public func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        if presenter == nil {
            let presenter = Presenter(url: root, onChange: onChange)
            self.presenter = presenter
            NSFileCoordinator.addFilePresenter(presenter)
        }
        lock.unlock()
        fallback.start(onChange: onChange)
    }

    public func stop() {
        lock.lock()
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
        }
        lock.unlock()
        fallback.stop()
    }

    /// The presenter itself. `NSFilePresenter` requires an `NSObject` and its own operation
    /// queue; everything it reports collapses into the same "something changed" signal.
    private final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue
        private let onChange: @Sendable () -> Void

        init(url: URL, onChange: @escaping @Sendable () -> Void) {
            self.presentedItemURL = url
            self.onChange = onChange
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            self.presentedItemOperationQueue = queue
            super.init()
        }

        func presentedItemDidChange() { onChange() }

        func presentedSubitemDidChange(at url: URL) { onChange() }

        func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }

        func presentedSubitemDidAppear(at url: URL) { onChange() }

        func accommodatePresentedSubitemDeletion(
            at url: URL, completionHandler: @escaping ((any Error)?) -> Void
        ) {
            onChange()
            completionHandler(nil)
        }
    }
}
#endif
