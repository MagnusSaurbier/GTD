import Foundation

/// The fake `VaultFileSystem` tests run against — no disk, no coordination, no iCloud.
///
/// It also models the two failure modes the real one has and tests otherwise cannot produce:
/// `failWrites(matching:)` makes a write fail so rollback can be exercised, and
/// `evict(_:)` turns a file into an undownloaded iCloud item.
public final class InMemoryFileSystem: VaultFileSystem, @unchecked Sendable {
    private struct Node {
        var text: String
        var modified: Date
        var isDownloaded: Bool
    }

    private let lock = NSLock()
    private var files: [String: Node] = [:]
    private var folders: Set<String> = []
    private var failingWrites: Set<String> = []
    private var failingMoves: Set<String> = []
    private var downloadRequests: [String] = []
    private var clockTick: TimeInterval = 0

    public let root = URL(fileURLWithPath: "/in-memory-vault", isDirectory: true)

    /// The instant the next write is stamped with; every write advances it by one second so
    /// fingerprints change deterministically without sleeping.
    public var baseDate: Date

    public init(files: [String: String] = [:], baseDate: Date = Date(timeIntervalSince1970: 1_600_000_000)) {
        self.baseDate = baseDate
        for (path, text) in files { writeIgnoringFailures(text, to: path) }
    }

    // MARK: Test controls

    /// Vault-relative paths whose next write should fail with `VaultError.ioFailed`.
    public func failWrites(matching paths: [String]) {
        lock.lock(); defer { lock.unlock() }
        failingWrites = Set(paths.map(VaultPath.normalize))
    }

    /// Vault-relative *destination* paths whose next move should fail.
    public func failMoves(to paths: [String]) {
        lock.lock(); defer { lock.unlock() }
        failingMoves = Set(paths.map(VaultPath.normalize))
    }

    /// Turns a file into an evicted iCloud item: it is listed but cannot be read.
    public func evict(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        files[VaultPath.normalize(path)]?.isDownloaded = false
    }

    /// Paths `requestDownload` was called for, in order.
    public var requestedDownloads: [String] {
        lock.lock(); defer { lock.unlock() }
        return downloadRequests
    }

    /// Path → text of everything currently stored, for byte-identical assertions.
    public var snapshotOfFiles: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return files.mapValues(\.text)
    }

    /// Writes without honouring `failWrites` — used by `init` and by tests setting up state.
    public func writeIgnoringFailures(_ text: String, to path: String) {
        lock.lock(); defer { lock.unlock() }
        store(text, at: VaultPath.normalize(path))
    }

    // MARK: VaultFileSystem

    public func listFiles() throws -> [VaultFileInfo] {
        lock.lock(); defer { lock.unlock() }
        return files.map { path, node in
            VaultFileInfo(path: path, size: node.text.utf8.count, modified: node.modified,
                          isDownloaded: node.isDownloaded)
        }.sorted { $0.path < $1.path }
    }

    public func listFolders() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        var all = folders
        for path in files.keys {
            var parts = path.split(separator: "/").map(String.init)
            parts.removeLast()
            while !parts.isEmpty {
                all.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        return all.sorted()
    }

    public func info(_ path: String) throws -> VaultFileInfo? {
        lock.lock(); defer { lock.unlock() }
        let key = VaultPath.normalize(path)
        guard let node = files[key] else { return nil }
        return VaultFileInfo(path: key, size: node.text.utf8.count, modified: node.modified,
                             isDownloaded: node.isDownloaded)
    }

    public func exists(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[VaultPath.normalize(path)] != nil
    }

    public func readText(_ path: String) throws -> String? {
        lock.lock()
        let key = VaultPath.normalize(path)
        guard let node = files[key] else { lock.unlock(); return nil }
        guard node.isDownloaded else {
            downloadRequests.append(key)
            lock.unlock()
            throw VaultError.notDownloaded(path: key)
        }
        lock.unlock()
        return node.text
    }

    public func writeText(_ text: String, to path: String) throws {
        lock.lock(); defer { lock.unlock() }
        let key = VaultPath.normalize(path)
        guard VaultPath.isSafe(key) else {
            throw VaultError.ioFailed(path: path, reason: "path escapes the vault root")
        }
        if failingWrites.contains(key) {
            throw VaultError.ioFailed(path: key, reason: "injected write failure")
        }
        store(text, at: key)
    }

    public func move(_ from: String, to path: String) throws {
        lock.lock(); defer { lock.unlock() }
        let source = VaultPath.normalize(from)
        let destination = VaultPath.normalize(path)
        guard let node = files[source] else {
            throw VaultError.ioFailed(path: source, reason: "no such file")
        }
        guard files[destination] == nil else {
            throw VaultError.destinationExists(path: destination)
        }
        if failingMoves.contains(destination) {
            throw VaultError.ioFailed(path: destination, reason: "injected move failure")
        }
        files[source] = nil
        files[destination] = node
    }

    public func createFolder(_ path: String) throws {
        lock.lock(); defer { lock.unlock() }
        let key = VaultPath.normalize(path)
        guard !key.isEmpty else { return }
        folders.insert(key)
    }

    public func requestDownload(_ path: String) throws {
        lock.lock(); defer { lock.unlock() }
        downloadRequests.append(VaultPath.normalize(path))
    }

    // MARK: Private

    private func store(_ text: String, at key: String) {
        clockTick += 1
        files[key] = Node(text: text, modified: baseDate.addingTimeInterval(clockTick),
                          isDownloaded: true)
        var parts = key.split(separator: "/").map(String.init)
        parts.removeLast()
        while !parts.isEmpty {
            folders.insert(parts.joined(separator: "/"))
            parts.removeLast()
        }
    }
}
