#if !(os(iOS) || os(macOS))
import Foundation

/// Non-Apple builds (the Linux CI the build-out runs on): no `NSFileCoordinator`, no
/// security-scoped bookmarks, no `NSFilePresenter`. Plain `FileManager` and mtime polling.
extension VaultPlatform {
    public static func makeFileSystem(root: URL) -> any VaultFileSystem {
        PlainFileSystem(root: root)
    }

    public static func makeBookmarkStore() -> any BookmarkStore {
        PathBookmarkStore()
    }

    public static func makeWatcher(
        fileSystem: any VaultFileSystem, clock: any VaultClock
    ) -> any VaultWatcher {
        PollingVaultWatcher(fileSystem: fileSystem, interval: 5, clock: clock)
    }
}
#endif
