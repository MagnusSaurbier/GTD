import Foundation
import GTDAppCore

/// The crash journal's file (#56): `Application Support/GTD/unsaved-text.json`, next to the
/// undo journal — device-local, **never** in the vault (ARCHITECTURE §3).
///
/// A missing file is an empty journal. An unreadable one throws, and is not overwritten until
/// the next change: the journal reports the failure instead of silently starting empty.
/// Written atomically, so a crash mid-write leaves the previous version.
public struct FileUnsavedTextStore: UnsavedTextStore {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `unsaved-text.json` in `UndoJournal.defaultDirectory`; `nil` when there is no
    /// Application Support. Fixture runs pass their own name so they never touch the real one.
    public static func standard(fileName: String = "unsaved-text.json") -> FileUnsavedTextStore? {
        UndoJournal.defaultDirectory.map { FileUnsavedTextStore(file: $0.appendingPathComponent(fileName)) }
    }

    public func load() throws -> [UnsavedText] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        return try Self.decoder.decode([UnsavedText].self, from: data)
    }

    public func save(_ entries: [UnsavedText]) throws {
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
