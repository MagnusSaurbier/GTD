import Foundation

/// `FileManager`-only `VaultFileSystem`. Compiles and runs everywhere, including Linux, and is
/// the base the Apple-only `CoordinatedFileSystem` wraps in `NSFileCoordinator` calls.
///
/// It still understands iCloud *eviction*, because an evicted item is visible as a hidden
/// `.<name>.icloud` placeholder — plain string work that needs no Apple API. Actually *asking*
/// for the download does need one, so `requestDownload` is a no-op here.
public struct PlainFileSystem: VaultFileSystem {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    // MARK: URLs

    func url(_ path: String) throws -> URL {
        guard VaultPath.isSafe(path) else {
            throw VaultError.ioFailed(path: path, reason: "path escapes the vault root")
        }
        return root.appendingPathComponent(VaultPath.normalize(path))
    }

    // MARK: Listing

    public func listFiles() throws -> [VaultFileInfo] {
        var files: [String: VaultFileInfo] = [:]
        var evicted: Set<String> = []

        for entry in try walk() where !entry.isDirectory {
            // `.foo.md.icloud` is the placeholder iCloud leaves behind when it evicts `foo.md`.
            if let original = VaultPath.evictedOriginal(of: entry.path) {
                evicted.insert(original)
                continue
            }
            guard !VaultPath.name(of: entry.path).hasPrefix(".") else { continue }
            files[entry.path] = VaultFileInfo(
                path: entry.path, size: entry.size, modified: entry.modified)
        }

        for path in evicted {
            // An evicted file has no readable content; report it with a zero fingerprint so the
            // index re-reads it the moment iCloud materialises it.
            files[path] = files[path].map {
                VaultFileInfo(path: $0.path, size: $0.size, modified: $0.modified, isDownloaded: false)
            } ?? VaultFileInfo(path: path, size: 0, modified: Date(timeIntervalSince1970: 0),
                               isDownloaded: false)
        }
        return files.values.sorted { $0.path < $1.path }
    }

    public func listFolders() throws -> [String] {
        try walk().filter(\.isDirectory).map(\.path).sorted()
    }

    struct Entry {
        var path: String
        var isDirectory: Bool
        var size: Int
        var modified: Date
    }

    /// Recursive walk that keeps `.icloud` placeholders (they are hidden) but skips every other
    /// dot file and never follows a package or symlink out of the vault.
    func walk() throws -> [Entry] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw VaultError.ioFailed(path: "", reason: "vault root does not exist") }

        var out: [Entry] = []
        var queue: [String] = [""]
        while let folder = queue.popLast() {
            let folderURL = folder.isEmpty ? root : root.appendingPathComponent(folder)
            let children: [URL]
            do {
                children = try manager.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                        .contentModificationDateKey,
                    ],
                    options: [])
            } catch {
                throw VaultError.ioFailed(path: folder, reason: "\(error)")
            }
            for child in children {
                let name = child.lastPathComponent
                let path = VaultPath.join(folder, name)
                let values = try? child.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
                ])
                // A symlink could point outside the vault or form a cycle. Never follow one:
                // the vault root itself may be a symlink (it is standardised in `init`), but
                // nothing inside it is walked through.
                guard values?.isSymbolicLink != true else { continue }
                let directory = values?.isDirectory ?? false
                if directory {
                    guard !name.hasPrefix(".") else { continue }
                    out.append(Entry(path: path, isDirectory: true, size: 0,
                                     modified: values?.contentModificationDate ?? .distantPast))
                    queue.append(path)
                } else {
                    guard !name.hasPrefix(".") || VaultPath.evictedOriginal(of: path) != nil
                    else { continue }
                    out.append(Entry(
                        path: path, isDirectory: false,
                        size: values?.fileSize ?? 0,
                        modified: values?.contentModificationDate ?? .distantPast))
                }
            }
        }
        return out
    }

    // MARK: Single files

    public func info(_ path: String) throws -> VaultFileInfo? {
        let target = try url(path)
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            // Maybe it is evicted and only the placeholder is on disk.
            let placeholder = try url(VaultPath.join(
                VaultPath.folder(of: path), ".\(VaultPath.name(of: path)).icloud"))
            guard manager.fileExists(atPath: placeholder.path) else { return nil }
            return VaultFileInfo(path: VaultPath.normalize(path), size: 0,
                                 modified: Date(timeIntervalSince1970: 0), isDownloaded: false)
        }
        guard !isDirectory.boolValue else { return nil }
        let values = try? target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return VaultFileInfo(
            path: VaultPath.normalize(path),
            size: values?.fileSize ?? 0,
            modified: values?.contentModificationDate ?? .distantPast)
    }

    public func exists(_ path: String) -> Bool {
        guard let target = try? url(path) else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    public func readText(_ path: String) throws -> String? {
        let target = try url(path)
        guard FileManager.default.fileExists(atPath: target.path) else {
            if try info(path)?.isDownloaded == false {
                try? requestDownload(path)
                throw VaultError.notDownloaded(path: VaultPath.normalize(path))
            }
            return nil
        }
        do {
            let data = try Data(contentsOf: target)
            guard let text = String(data: data, encoding: .utf8) else {
                throw VaultError.ioFailed(path: path, reason: "file is not valid UTF-8")
            }
            return text
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.ioFailed(path: path, reason: "\(error)")
        }
    }

    public func writeText(_ text: String, to path: String) throws {
        let target = try url(path)
        try createFolder(VaultPath.folder(of: path))
        do {
            // `.atomic` writes a temporary file next to the target and renames it, so a crash or
            // an iCloud upload mid-write can never leave a half-written note (N3 §7.1).
            try Data(text.utf8).write(to: target, options: .atomic)
        } catch {
            throw VaultError.ioFailed(path: path, reason: "\(error)")
        }
    }

    public func move(_ from: String, to path: String) throws {
        let source = try url(from)
        let destination = try url(path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw VaultError.ioFailed(path: from, reason: "no such file")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VaultError.destinationExists(path: VaultPath.normalize(path))
        }
        try createFolder(VaultPath.folder(of: path))
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw VaultError.ioFailed(path: path, reason: "\(error)")
        }
    }

    public func createFolder(_ path: String) throws {
        let normalized = VaultPath.normalize(path)
        guard !normalized.isEmpty else { return }
        let target = try url(normalized)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw VaultError.ioFailed(path: normalized, reason: "\(error)")
        }
    }

    /// No iCloud outside Apple platforms — `CoordinatedFileSystem` overrides this.
    public func requestDownload(_ path: String) throws {}
}
