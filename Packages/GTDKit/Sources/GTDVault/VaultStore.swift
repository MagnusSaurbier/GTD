import Foundation
import GTDModel

/// The only module that touches the file system (ARCHITECTURE §2). **Owned by T15.**
public protocol VaultStore: Sendable {
    func snapshots() -> AsyncStream<VaultSnapshot>
    func read(path: String) async throws -> String?
    /// Applies the operations in order and returns the inverse ops, for the undo journal.
    /// A `.delete` moves the file into `GTD/Trash/` — the app never hard-deletes (N3).
    func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp]
}

public enum VaultError: Error, Equatable {
    case notImplemented(String)
    case noVaultSelected
    case bookmarkStale
    case notDownloaded(path: String)
    case ioFailed(path: String, reason: String)
}

/// Picks, persists and resolves the security-scoped bookmark to the vault root. **Owned by T15.**
///
/// The real implementation is platform-only (`URL.bookmarkData(options:)` differs per OS) and
/// lives in a file guarded by `#if os(iOS) || os(macOS)`; this type is the Linux-compilable shell
/// so dependants can name it.
public final class VaultBookmark: Sendable {
    public init() {}

    /// Stores a bookmark for a folder the user picked.
    public func save(url: URL) throws {
        throw VaultError.notImplemented("T15: VaultBookmark.save")
    }

    /// Resolves the stored bookmark, refreshing it when stale.
    public func resolve() throws -> URL {
        throw VaultError.notImplemented("T15: VaultBookmark.resolve")
    }

    public func startAccess() -> Bool { false }
    public func stopAccess() {}
}

/// Standalone capture writer: writes one file into `Inbox/` without loading or indexing the
/// vault (C1, used by the App Intents in T30). **Owned by T15.**
public struct InboxWriter: Sendable {
    public var layout: VaultLayout
    public var bookmark: VaultBookmark

    public init(layout: VaultLayout = .default, bookmark: VaultBookmark = VaultBookmark()) {
        self.layout = layout
        self.bookmark = bookmark
    }

    public func capture(text: String, at date: Date) throws -> NoteID {
        throw VaultError.notImplemented("T15: InboxWriter.capture")
    }
}

/// Scans the vault, watches it for changes and commits file operations. **Owned by T15.**
public actor FileVaultStore: VaultStore {
    public init(root: URL, layout: VaultLayout = .default) {
        self.root = root
        self.layout = layout
    }

    private let root: URL
    private let layout: VaultLayout

    nonisolated public func snapshots() -> AsyncStream<VaultSnapshot> {
        AsyncStream { $0.finish() }   // T15
    }

    public func read(path: String) async throws -> String? {
        throw VaultError.notImplemented("T15: FileVaultStore.read")
    }

    public func commit(_ ops: [VaultFileOp]) async throws -> [VaultFileOp] {
        throw VaultError.notImplemented("T15: FileVaultStore.commit")
    }
}
