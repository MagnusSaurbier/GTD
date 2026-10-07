import Foundation

/// What the store knows about one file in the vault.
///
/// `size` + `modified` are the incremental index's cache key: when neither changed, the cached
/// decode is reused (performance budget: incremental update < 50 ms).
public struct VaultFileInfo: Sendable, Equatable, Hashable {
    /// Vault-relative, "/"-separated, no leading slash.
    public var path: String
    public var size: Int
    public var modified: Date
    /// The file's birth (creation) time, `nil` where the file system or platform reports none.
    /// Not part of the fingerprint: an atomic save — every app write — replaces the file and
    /// with it the birth time, and it always changes `modified` too.
    public var created: Date?
    /// `false` for an iCloud item that has been evicted and only exists as a `.…​.icloud`
    /// placeholder. Such files are reported as `VaultIssue`s until the download finishes (N3 §7.4).
    public var isDownloaded: Bool

    public init(
        path: String, size: Int, modified: Date, created: Date? = nil, isDownloaded: Bool = true
    ) {
        self.path = path
        self.size = size
        self.modified = modified
        self.created = created
        self.isDownloaded = isDownloaded
    }

    /// When this file came into being, for a capture that does not say so itself (an inbox note
    /// without `created`, #89): the birth time, or the modification time where there is none.
    /// The earlier of the two wins — a copy or a restore can carry an old modification time
    /// into a new file, and the content cannot be younger than its last change.
    public var captureDate: Date {
        guard let created else { return modified }
        return min(created, modified)
    }

    /// Cache key of the incremental index — any change means "read and decode again".
    public var fingerprint: String {
        "\(size)@\(modified.timeIntervalSince1970)@\(isDownloaded ? 1 : 0)"
    }
}

/// One directory walk's worth of listing: the files and the folders below the vault root.
///
/// The index needs both on every refresh, and asking for them separately means walking the whole
/// tree twice — twice the `NSFileCoordinator` round trips on a real vault (T41 measured ~100 ms
/// of the ~320 ms no-op refresh of a 1 000-note vault on the second walk alone).
public struct VaultListing: Sendable, Equatable {
    public var files: [VaultFileInfo]
    public var folders: [String]

    public init(files: [VaultFileInfo], folders: [String]) {
        self.files = files
        self.folders = folders
    }
}

/// Everything `GTDVault` is allowed to do to the file system.
///
/// **There is deliberately no delete.** The app never hard-deletes a vault file (ARCHITECTURE §3);
/// `VaultFileOp.delete` is implemented as a move into `GTD/Trash/`, so no code path in the whole
/// app can remove user data. Implementations:
///
/// - `PlainFileSystem` — `FileManager` only, works everywhere including Linux.
/// - `CoordinatedFileSystem` — `NSFileCoordinator` + iCloud downloads, Apple platforms only.
/// - `InMemoryFileSystem` — the fake used by tests.
public protocol VaultFileSystem: Sendable {
    /// The vault root. Informational — every other method takes vault-relative paths.
    var root: URL { get }

    /// Every regular file below the root, recursively, hidden files excluded.
    func listFiles() throws -> [VaultFileInfo]

    /// Every folder below the root, recursively, vault-relative, hidden folders excluded.
    func listFolders() throws -> [String]

    /// Both listings from **one** walk of the tree. The default below is correct but walks
    /// twice; every implementation in this module overrides it.
    func listEntries() throws -> VaultListing

    func info(_ path: String) throws -> VaultFileInfo?

    /// True when a **file** lives at `path`. `PlainFileSystem` answers for a directory too (that
    /// is what `FileManager` does); ask ``folderExists(_:)`` when the answer has to be exact.
    func exists(_ path: String) -> Bool

    /// True when a **folder** lives at `path`. Needed because a folder move must refuse a
    /// destination that is taken by either kind (R-5), and `exists(_:)` cannot see an
    /// `InMemoryFileSystem` folder at all.
    func folderExists(_ path: String) -> Bool

    /// `nil` when the file does not exist. Throws `VaultError.notDownloaded` for an evicted
    /// iCloud item (and asks for the download).
    func readText(_ path: String) throws -> String?

    /// Atomic: writes to a temporary file and replaces. Creates intermediate folders.
    func writeText(_ text: String, to path: String) throws

    /// Creates intermediate folders for the destination. Fails if the destination exists.
    func move(_ from: String, to path: String) throws

    /// Moves a directory and everything below it in **one** step (R-5). Creates intermediate
    /// folders for the destination, fails if the destination exists in any form, and fails if
    /// `from` is not a folder. It is a rename, never a removal: no content is dropped.
    func moveFolder(_ from: String, to path: String) throws

    func createFolder(_ path: String) throws

    /// Asks iCloud to materialise an evicted item. A no-op where there is no iCloud.
    func requestDownload(_ path: String) throws
}

extension VaultFileSystem {
    /// A conforming type that only implements the two separate listings still works — it just
    /// pays for two walks.
    public func listEntries() throws -> VaultListing {
        VaultListing(files: try listFiles(), folders: try listFolders())
    }
}

// MARK: - Path helpers shared by the implementations

enum VaultPath {
    /// Normalises to a vault-relative, "/"-separated path without leading, trailing or repeated
    /// separators. Rejects nothing — callers guard against escapes with ``isSafe(_:)``.
    static func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    /// False for a path that would escape the vault root or is empty.
    static func isSafe(_ path: String) -> Bool {
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return false }
        return !normalized.split(separator: "/").contains("..")
    }

    static func folder(of path: String) -> String {
        var parts = normalize(path).split(separator: "/").map(String.init)
        guard parts.count > 1 else { return "" }
        parts.removeLast()
        return parts.joined(separator: "/")
    }

    static func name(of path: String) -> String {
        normalize(path).split(separator: "/").last.map(String.init) ?? ""
    }

    /// Filename without its extension.
    static func stem(of path: String) -> String {
        let file = name(of: path)
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return file }
        return String(file[file.startIndex..<dot])
    }

    static func `extension`(of path: String) -> String {
        let file = name(of: path)
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return "" }
        return String(file[file.index(after: dot)...])
    }

    static func isMarkdown(_ path: String) -> Bool { `extension`(of: path).lowercased() == "md" }

    static func join(_ folder: String, _ name: String) -> String {
        let f = normalize(folder)
        return f.isEmpty ? normalize(name) : "\(f)/\(normalize(name))"
    }

    /// True when `path` is `folder` itself or lies below it.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        let f = normalize(folder)
        guard !f.isEmpty else { return true }
        let p = normalize(path)
        return p == f || p.hasPrefix(f + "/")
    }

    /// `url` as a vault-relative path, or `nil` when it is the root itself or lies outside it.
    /// Both sides are compared with symlinks resolved: the file-event APIs report real paths
    /// (`/private/var/…`), while the root is usually the path the person picked.
    static func relative(_ url: URL, to root: URL) -> String? {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let full = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard full.hasPrefix(base + "/") else { return nil }
        let path = normalize(String(full.dropFirst(base.count + 1)))
        return isSafe(path) ? path : nil
    }

    /// iCloud evicts a file to a hidden placeholder `.<name>.icloud` in the same folder.
    /// Returns the path of the real file when `path` is such a placeholder.
    static func evictedOriginal(of path: String) -> String? {
        let file = name(of: path)
        guard file.hasPrefix("."), file.hasSuffix(".icloud"), file.count > ".".count + ".icloud".count
        else { return nil }
        let original = String(file.dropFirst().dropLast(".icloud".count))
        guard !original.isEmpty else { return nil }
        return join(folder(of: path), original)
    }
}
