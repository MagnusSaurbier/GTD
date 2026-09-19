import Foundation
import GTDModel

/// Device-local undo stack (N6).
///
/// One entry = a human-readable label, the **inverse ops** `VaultStore.commit` handed back
/// (already in undo order), and a content hash per file the undo would touch. The hashes are
/// what makes undo safe in a synced vault: if any of those files changed in the meantime — a
/// sync landing, Obsidian on the Mac, another device — the undo is refused with
/// `ServiceError.undoStale` instead of silently overwriting the newer version (N3).
///
/// N6 only requires depth 1; the journal keeps `capacity` (20) entries so a later task can
/// deepen undo without touching the file format. It is stored in Application Support, **never**
/// in the vault (ARCHITECTURE §3), and survives relaunch.
public actor UndoJournal {

    public struct Entry: Sendable, Equatable {
        public var label: String
        public var inverseOps: [VaultFileOp]
        /// Content hashes of the files the undo would overwrite; undo is refused when they moved.
        public var hashes: [String: String]

        public init(label: String, inverseOps: [VaultFileOp], hashes: [String: String]) {
            self.label = label
            self.inverseOps = inverseOps
            self.hashes = hashes
        }
    }

    public static let capacity = 20

    private let file: URL?
    private var entries: [Entry]?      // nil until loaded

    /// The contract initialiser: `~/Library/Application Support/GTD/undo-journal.json`
    /// (or the platform's equivalent). Falls back to memory only when that folder is unusable.
    public init() {
        self.init(directory: UndoJournal.defaultDirectory)
    }

    /// Full initialiser — tests pass a temp directory, `nil` keeps the journal in memory.
    public init(directory: URL?, fileName: String = "undo-journal.json") {
        self.file = directory?.appendingPathComponent(fileName)
    }

    /// `Application Support/GTD` — device-local state, outside the vault.
    public static var defaultDirectory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("GTD", isDirectory: true)
    }

    // MARK: Stack

    public func push(_ entry: Entry) {
        var stack = load()
        stack.append(entry)
        if stack.count > Self.capacity { stack.removeFirst(stack.count - Self.capacity) }
        entries = stack
        save()
    }

    /// The entry `undo()` would apply, without consuming it.
    public func peek() -> Entry? { load().last }

    @discardableResult
    public func pop() -> Entry? {
        var stack = load()
        let last = stack.popLast()
        entries = stack
        save()
        return last
    }

    public func clear() {
        entries = []
        save()
    }

    public var count: Int { load().count }

    // MARK: Persistence

    private func load() -> [Entry] {
        if let entries { return entries }
        guard let file, let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode([StoredEntry].self, from: data)
        else {
            entries = []
            return []
        }
        let loaded = stored.map(\.entry)
        entries = loaded
        return loaded
    }

    private func save() {
        guard let file, let entries else { return }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries.map(StoredEntry.init)) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Codable mirror

    /// `VaultFileOp` is not `Codable` (it is a contract type in `GTDModel`), so the journal
    /// carries its own on-disk shape. Unknown kinds are dropped rather than crashing a launch.
    private struct StoredOp: Codable {
        var kind: String
        var path: String?
        var text: String?
        var from: String?
        var to: String?

        init(_ op: VaultFileOp) {
            switch op {
            case let .put(path, text):
                kind = "put"; self.path = path; self.text = text
            case let .move(from, to):
                kind = "move"; self.from = from; self.to = to
            case let .delete(path):
                kind = "delete"; self.path = path
            }
        }

        var op: VaultFileOp? {
            switch kind {
            case "put": path.map { .put(path: $0, text: text ?? "") }
            case "move": from.flatMap { f in to.map { .move(from: f, to: $0) } }
            case "delete": path.map { .delete(path: $0) }
            default: nil
            }
        }
    }

    private struct StoredEntry: Codable {
        var label: String
        var ops: [StoredOp]
        var hashes: [String: String]

        init(_ entry: Entry) {
            label = entry.label
            ops = entry.inverseOps.map(StoredOp.init)
            hashes = entry.hashes
        }

        var entry: Entry {
            Entry(label: label, inverseOps: ops.compactMap(\.op), hashes: hashes)
        }
    }
}
