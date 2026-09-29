import Foundation

/// The platform half of `VaultBookmark`: everything about it that needs an Apple API.
///
/// `SecurityScopedBookmarkStore` (iOS/macOS) creates real security-scoped bookmarks;
/// `PathBookmarkStore` just remembers the path and is what Linux and the unit tests use.
public protocol BookmarkStore: Sendable {
    func bookmarkData(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
    /// `false` when access was refused — the caller must not read or write.
    func startAccess(_ url: URL) -> Bool
    func stopAccess(_ url: URL)
}

/// Stores the folder's path and nothing else. No sandbox, so no scoped access is needed.
public struct PathBookmarkStore: BookmarkStore {
    public init() {}

    public func bookmarkData(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    public func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8), !path.isEmpty else {
            throw VaultError.bookmarkStale
        }
        return (URL(fileURLWithPath: path, isDirectory: true), false)
    }

    public func startAccess(_ url: URL) -> Bool { true }
    public func stopAccess(_ url: URL) {}
}

/// Picks, persists and resolves the durable reference to the vault root (N1).
///
/// The app cannot keep a plain path: on iOS the user picks the folder in a document picker and
/// only a **security-scoped bookmark** survives a relaunch; on sandboxed macOS the same is true.
/// The bookmark lives in Application Support, never in the vault (ARCHITECTURE §3), and
/// `startAccess()` must bracket every access on the real platforms.
///
/// Stale bookmarks are refreshed transparently: iCloud moves the container often enough that a
/// stale bookmark is normal, not an error.
public final class VaultBookmark: @unchecked Sendable {
    private let store: any BookmarkStore
    private let fileURL: URL
    private let lock = NSLock()
    private var accessing: URL?

    /// The contract initialiser (ARCHITECTURE §4): the platform's bookmark store, the standard
    /// Application Support location.
    public convenience init() {
        self.init(store: VaultPlatform.makeBookmarkStore(), fileURL: VaultBookmark.defaultFileURL())
    }

    public init(store: any BookmarkStore, fileURL: URL) {
        self.store = store
        self.fileURL = fileURL
    }

    /// `<Application Support>/GTD/vault-bookmark.data`. Falls back to the temporary directory
    /// when Application Support cannot be created, so `init()` never traps.
    public static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = base.appendingPathComponent("GTD", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("vault-bookmark.data")
    }

    public var hasSavedVault: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Stores a bookmark for a folder the user picked.
    public func save(url: URL) throws {
        let data: Data
        // A URL handed over by `.fileImporter` is security-scoped: without access the sandbox
        // refuses to bookmark it ("Could not open() the item"). `false` just means the URL needs
        // no scope (tests, an already-open vault), so it is not an error.
        let opened = store.startAccess(url)
        defer { if opened { store.stopAccess(url) } }
        do {
            data = try store.bookmarkData(for: url)
        } catch {
            throw VaultError.ioFailed(path: url.path, reason: "could not bookmark: \(error)")
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw VaultError.ioFailed(path: fileURL.path, reason: "\(error)")
        }
    }

    /// Runs `body` with security-scoped access to a folder the user just picked — the location a
    /// new vault is created in (#60). Creating the vault folder inside it and bookmarking that
    /// folder (`save(url:)`) both need the location's scope open, so both go inside `body`.
    /// `false` from the store just means the URL needs no scope (tests, Linux).
    /// Synchronous on purpose: the scope is held only for the file work, not across an `await`.
    public func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let opened = store.startAccess(url)
        defer { if opened { store.stopAccess(url) } }
        return try body()
    }

    /// Resolves the stored bookmark, re-saving it when the system reports it stale.
    public func resolve() throws -> URL {
        guard let data = try? Data(contentsOf: fileURL) else { throw VaultError.noVaultSelected }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try store.resolve(data)
        } catch {
            throw VaultError.bookmarkStale
        }
        if resolved.isStale {
            // Refreshing needs access, so bracket it; a failure here is not fatal — the resolved
            // URL still works for this launch.
            let opened = store.startAccess(resolved.url)
            defer { if opened { store.stopAccess(resolved.url) } }
            try? save(url: resolved.url)
        }
        return resolved.url
    }

    /// Begins security-scoped access to the resolved vault. Balance with `stopAccess()`.
    public func startAccess() -> Bool {
        guard let url = try? resolve() else { return false }
        lock.lock(); defer { lock.unlock() }
        if let accessing, accessing == url { return true }
        guard store.startAccess(url) else { return false }
        accessing = url
        return true
    }

    public func stopAccess() {
        lock.lock(); defer { lock.unlock() }
        guard let url = accessing else { return }
        store.stopAccess(url)
        accessing = nil
    }

    /// Forgets the vault (onboarding "choose a different folder").
    public func clear() throws {
        stopAccess()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            // The bookmark is device-local app state, not vault data — removing it is allowed.
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw VaultError.ioFailed(path: fileURL.path, reason: "\(error)")
        }
    }
}
