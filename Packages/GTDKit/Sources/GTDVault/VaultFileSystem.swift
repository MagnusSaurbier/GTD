import Foundation

/// What the store knows about one file in the vault.
///
/// `size` + `modified` are the incremental index's cache key: when neither changed, the cached
/// decode is reused (T15 performance budget: incremental update < 50 ms).
public struct VaultFileInfo: Sendable, Equatable, Hashable {
    /// Vault-relative, "/"-separated, no leading slash.
    public var path: String
    public var size: Int
    public var modified: Date
    /// `false` for an iCloud item that has been evicted and only exists as a `.…​.icloud`
    /// placeholder. Such files are reported as `VaultIssue`s until the download finishes (N3 §7.4).
    public var isDownloaded: Bool

    public init(path: String, size: Int, modified: Date, isDownloaded: Bool = true) {
        self.path = path
        self.size = size
        self.modified = modified
        self.isDownloaded = isDownloaded
    }

    /// Cache key of the incremental index — any change means "read and decode again".
    public var fingerprint: String {
        "\(size)@\(modified.timeIntervalSince1970)@\(isDownloaded ? 1 : 0)"
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

    func info(_ path: String) throws -> VaultFileInfo?
    func exists(_ path: String) -> Bool

    /// `nil` when the file does not exist. Throws `VaultError.notDownloaded` for an evicted
    /// iCloud item (and asks for the download).
    func readText(_ path: String) throws -> String?

    /// Atomic: writes to a temporary file and replaces. Creates intermediate folders.
    func writeText(_ text: String, to path: String) throws

    /// Creates intermediate folders for the destination. Fails if the destination exists.
    func move(_ from: String, to path: String) throws

    func createFolder(_ path: String) throws

    /// Asks iCloud to materialise an evicted item. A no-op where there is no iCloud.
    func requestDownload(_ path: String) throws
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
