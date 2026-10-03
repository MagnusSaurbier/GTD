import Foundation
import GTDAppCore

/// #94 — the dialog drafts' file: `Application Support/GTD/input-drafts.json`, next to the crash
/// journal — device-local, **never** in the vault (ARCHITECTURE §3).
///
/// A missing file is no drafts. An unreadable one throws and is not overwritten until the next
/// change (`InputDrafts.failure`). Written atomically, so a crash mid-write leaves the previous
/// version.
public struct FileInputDraftStore: InputDraftStore {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `input-drafts.json` in `UndoJournal.defaultDirectory`; `nil` when there is no
    /// Application Support. Fixture runs pass their own name so they never touch the real one.
    public static func standard(fileName: String = "input-drafts.json") -> FileInputDraftStore? {
        UndoJournal.defaultDirectory.map { FileInputDraftStore(file: $0.appendingPathComponent(fileName)) }
    }

    public func load() throws -> [String: InputDraft] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        return try Self.decoder.decode([String: InputDraft].self, from: data)
    }

    public func save(_ drafts: [String: InputDraft]) throws {
        if drafts.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(drafts).write(to: file, options: .atomic)
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
