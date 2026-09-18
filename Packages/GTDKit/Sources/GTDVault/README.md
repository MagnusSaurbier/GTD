# GTDVault

The only module that touches the file system: security-scoped bookmark, `NSFileCoordinator`-mediated I/O, the change watcher, and the scan that builds a `VaultSnapshot`. Public types: `VaultStore`, `FileVaultStore`, `VaultBookmark`, `InboxWriter`, `VaultError`.

**Owned by T15** — T00 created only the public signatures listed in `docs/ARCHITECTURE.md` §4
so that dependants compile. The bodies throw `notImplemented` or return empty values.

## Platform guards (ARCHITECTURE §5)

Keep the store, the path logic and an in-memory fake file system Foundation-only so they run on Linux. Bookmarks, `NSFileCoordinator`, `NSFilePresenter` and `startDownloadingUbiquitousItem` are Apple-only: put them in files wrapped entirely in `#if os(iOS) || os(macOS)` behind the `CoordinatedFileSystem` protocol, and note in your Result that they are unverified.

## Testing

`cd Packages/GTDKit && swift test --filter GTDVaultTests`
