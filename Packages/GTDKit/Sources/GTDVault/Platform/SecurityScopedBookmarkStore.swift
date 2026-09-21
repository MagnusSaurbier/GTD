#if os(iOS) || os(macOS)
import Foundation

/// Real security-scoped bookmarks.
///
/// The user picks the vault folder once; only a security-scoped bookmark survives a relaunch,
/// and access has to be bracketed by `startAccessingSecurityScopedResource()`. macOS needs the
/// `.withSecurityScope` option on both creation and resolution; iOS does not have it, hence the
/// `#if os(macOS)` split (ARCHITECTURE §6: T01 was skipped, so this is the assumption the app
/// rests on — if it turns out wrong, the fallback is the app-owned iCloud container).
///
/// **Compiled blind** — see `GTDVault/README.md`.
public struct SecurityScopedBookmarkStore: BookmarkStore {
    public init() {}

    public func bookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    public func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let url = try URL(
            resolvingBookmarkData: data, options: [],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        return (url, isStale)
    }

    public func startAccess(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccess(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
#endif
