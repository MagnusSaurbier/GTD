#if os(iOS) || os(macOS)
import Foundation

/// iOS and macOS: coordinated I/O, security-scoped bookmarks, `NSFilePresenter` watching.
///
/// **Compiled blind** — the build-out container has no Apple SDK. See `GTDVault/README.md`
/// "Unverified on Linux".
extension VaultPlatform {
    public static func makeFileSystem(root: URL) -> any VaultFileSystem {
        CoordinatedFileSystem(root: root)
    }

    public static func makeBookmarkStore() -> any BookmarkStore {
        SecurityScopedBookmarkStore()
    }

    public static func makeWatcher(
        fileSystem: any VaultFileSystem, clock: any VaultClock
    ) -> any VaultWatcher {
        let presenter = PresenterVaultWatcher(root: fileSystem.root, fallback: PollingVaultWatcher(
            fileSystem: fileSystem, interval: 5, clock: clock))
        #if os(macOS)
        // FSEvents first: it is the one that sees an uncoordinated write (Obsidian, a script)
        // the moment it happens. The presenter and the poll stay as they were.
        return CompositeVaultWatcher([FSEventsVaultWatcher(root: fileSystem.root), presenter])
        #else
        return presenter
        #endif
    }
}
#endif
