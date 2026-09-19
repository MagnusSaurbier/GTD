#if os(iOS) || os(macOS)
import Foundation

/// `PlainFileSystem` with every access wrapped in an `NSFileCoordinator` call (N3 §7.3) and with
/// real iCloud handling.
///
/// Obsidian, the Files app and iCloud's own sync daemon all write into the same folder; without
/// coordination a read can see a half-written file and a write can land on top of an incoming
/// sync. `NSFileCoordinator` is the only API that serialises those.
///
/// **Compiled blind** (no Apple SDK in the build-out container). Conservative by design: no
/// `NSFilePresenter` registration here, no `NSFileVersion` conflict resolution, plain
/// coordinate-and-do-the-same-thing-`PlainFileSystem`-does calls.
public struct CoordinatedFileSystem: VaultFileSystem {
    public let root: URL
    private let plain: PlainFileSystem
    /// Identifies this reader/writer to the coordinator so our own writes do not notify us back.
    private let purposeID: NSObject?

    public init(root: URL, purposeID: NSObject? = nil) {
        self.root = root.standardizedFileURL
        self.plain = PlainFileSystem(root: root)
        self.purposeID = purposeID
    }

    // MARK: Listing — coordinated on the root folder

    public func listFiles() throws -> [VaultFileInfo] {
        markEvicted(try coordinateRead(root) { _ in try plain.listFiles() })
    }

    public func listFolders() throws -> [String] {
        try coordinateRead(root) { _ in try plain.listFolders() }
    }

    /// One coordinated read of the root for both listings (T41). The index asks for files and
    /// folders on every refresh; two `coordinateRead`s of the whole vault per refresh is the
    /// expensive half of a no-op refresh on a real iCloud folder.
    public func listEntries() throws -> VaultListing {
        var listing = try coordinateRead(root) { _ in try plain.listEntries() }
        listing.files = markEvicted(listing.files)
        return listing
    }

    private func markEvicted(_ infos: [VaultFileInfo]) -> [VaultFileInfo] {
        var infos = infos
        for index in infos.indices where infos[index].isDownloaded {
            // The `.icloud` placeholder is not the only eviction signal: an item can be present
            // but not current. Trust the resource value when it says so.
            if let status = downloadStatus(of: infos[index].path), status != .current {
                infos[index].isDownloaded = false
            }
        }
        return infos
    }

    public func info(_ path: String) throws -> VaultFileInfo? {
        var info = try plain.info(path)
        if info?.isDownloaded == true, let status = downloadStatus(of: path), status != .current {
            info?.isDownloaded = false
        }
        return info
    }

    public func exists(_ path: String) -> Bool { plain.exists(path) }

    // MARK: Reading and writing

    public func readText(_ path: String) throws -> String? {
        if let status = downloadStatus(of: path), status != .current {
            try requestDownload(path)
            throw VaultError.notDownloaded(path: VaultPath.normalize(path))
        }
        let url = try plain.url(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try plain.readText(path)   // handles the `.icloud` placeholder case
        }
        return try coordinateRead(url) { coordinated in
            guard let data = try? Data(contentsOf: coordinated) else {
                throw VaultError.ioFailed(path: path, reason: "unreadable")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw VaultError.ioFailed(path: path, reason: "file is not valid UTF-8")
            }
            return text
        }
    }

    public func writeText(_ text: String, to path: String) throws {
        try createFolder(VaultPath.folder(of: path))
        let url = try plain.url(path)
        try coordinateWrite(url) { coordinated in
            do {
                try Data(text.utf8).write(to: coordinated, options: .atomic)
            } catch {
                throw VaultError.ioFailed(path: path, reason: "\(error)")
            }
        }
    }

    public func move(_ from: String, to path: String) throws {
        let source = try plain.url(from)
        let destination = try plain.url(path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw VaultError.ioFailed(path: from, reason: "no such file")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VaultError.destinationExists(path: VaultPath.normalize(path))
        }
        try createFolder(VaultPath.folder(of: path))

        var coordinationError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { newSource, newDestination in
            do {
                try FileManager.default.moveItem(at: newSource, to: newDestination)
            } catch {
                thrown = VaultError.ioFailed(path: path, reason: "\(error)")
            }
        }
        if let thrown { throw thrown }
        if let coordinationError {
            throw VaultError.ioFailed(path: path, reason: "\(coordinationError)")
        }
    }

    public func createFolder(_ path: String) throws { try plain.createFolder(path) }

    // MARK: iCloud (N3 §7.4)

    public func requestDownload(_ path: String) throws {
        guard let url = try? plain.url(path) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private func downloadStatus(of path: String) -> URLUbiquitousItemDownloadingStatus? {
        guard let url = try? plain.url(path),
              let values = try? url.resourceValues(forKeys: [
                  .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
              ]),
              values.isUbiquitousItem == true
        else { return nil }
        return values.ubiquitousItemDownloadingStatus
    }

    // MARK: Coordination plumbing

    private func coordinateRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        var result: Result<T, any Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [.withoutChanges], error: &coordinationError
        ) { coordinated in
            result = Result { try body(coordinated) }
        }
        if let coordinationError {
            throw VaultError.ioFailed(
                path: url.lastPathComponent, reason: "\(coordinationError)")
        }
        guard let result else {
            throw VaultError.ioFailed(path: url.lastPathComponent, reason: "coordination produced no result")
        }
        return try result.get()
    }

    private func coordinateWrite(_ url: URL, _ body: (URL) throws -> Void) throws {
        var thrown: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: [.forReplacing], error: &coordinationError
        ) { coordinated in
            do { try body(coordinated) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        if let coordinationError {
            throw VaultError.ioFailed(path: url.lastPathComponent, reason: "\(coordinationError)")
        }
    }
}
#endif
