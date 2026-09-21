#if os(macOS)
import CoreServices
import Foundation

/// FSEvents on the vault root — what makes the Mac app as quick as Obsidian.
///
/// `NSFilePresenter` only hears about *coordinated* writes and iCloud's own. Obsidian, a script,
/// `echo > Inbox/x.md`, a git checkout: none of them coordinate, so before this watcher existed
/// such a write waited for the 5 s poll. FSEvents reports every change below the root whoever
/// made it, per file (`kFSEventStreamCreateFlagFileEvents`), after `latency` seconds — and the
/// paths it delivers become the store's hint, so the re-index touches those files only.
///
/// Anything that is not a plain file event — a folder created, renamed or removed, a dropped
/// event, the root itself moving — is reported as `.unknown` and costs one walk.
public final class FSEventsVaultWatcher: VaultWatcher, @unchecked Sendable {
    private let root: URL
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "gtd.vault.fsevents", qos: .userInitiated)
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var box: Unmanaged<Box>?

    public init(root: URL, latency: TimeInterval = 0.05) {
        self.root = root
        self.latency = latency
    }

    deinit { stop() }

    public func start(onChange: @escaping @Sendable (VaultChange) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }

        let box = Unmanaged.passRetained(Box(root: root, onChange: onChange))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagUseCFTypes
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, Self.callback, &context,
            [root.resolvingSymlinksInPath().path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(flags))
        else {
            box.release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            box.release()
            return
        }
        self.stream = stream
        self.box = box
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        box?.release()
        box = nil
    }

    /// What the C callback gets back through `info`.
    private final class Box {
        let root: URL
        let onChange: @Sendable (VaultChange) -> Void
        init(root: URL, onChange: @escaping @Sendable (VaultChange) -> Void) {
            self.root = root
            self.onChange = onChange
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else {
            box.onChange(.unknown)
            return
        }
        box.onChange(FSEventsVaultWatcher.change(
            paths: paths,
            flags: Array(UnsafeBufferPointer(start: flags, count: count)),
            root: box.root))
    }

    /// The decision, apart from the C plumbing so it can be tested.
    static func change(
        paths: [String], flags: [FSEventStreamEventFlags], root: URL
    ) -> VaultChange {
        let notAFileEvent = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount
                | kFSEventStreamEventFlagUnmount
                | kFSEventStreamEventFlagItemIsDir)
        var hinted: Set<String> = []
        for (path, flag) in zip(paths, flags) {
            guard flag & notAFileEvent == 0 else { return .unknown }
            guard let relative = VaultPath.relative(URL(fileURLWithPath: path), to: root)
            else { return .unknown }
            hinted.insert(relative)
        }
        return hinted.isEmpty ? .unknown : .paths(hinted)
    }
}
#endif
