import Foundation
import GTDModel
import Yams

/// Markdown ⇄ model. **Owned by T10** — every body here is a stub.
///
/// Invariant that must survive T10 (N2): `encode(decode(text)) == text` for every file in the
/// sample vault. Unknown frontmatter keys, their order, and unknown body sections survive in
/// `NotePassthrough`.
public enum NoteCodec {

    // MARK: - Decode

    public static func decodeInboxItem(id: NoteID, text: String) throws -> InboxItem {
        throw NoteCodecError.notImplemented("T10: decodeInboxItem")
    }

    public static func decodeAction(id: NoteID, text: String) throws -> Action {
        throw NoteCodecError.notImplemented("T10: decodeAction")
    }

    public static func decodeArea(id: NoteID, text: String) throws -> Area {
        throw NoteCodecError.notImplemented("T10: decodeArea")
    }

    public static func decodeProject(id: NoteID, text: String) throws -> Project {
        throw NoteCodecError.notImplemented("T10: decodeProject")
    }

    public static func decodeRoutine(id: NoteID, text: String) throws -> Routine {
        throw NoteCodecError.notImplemented("T10: decodeRoutine")
    }

    /// One `GTD/RoutineLog/<day>--<device>.md` file.
    public static func decodeRoutineLog(id: NoteID, text: String) throws -> [RoutineLogEntry] {
        throw NoteCodecError.notImplemented("T10: decodeRoutineLog")
    }

    public static func decodeConfig(id: NoteID, text: String) throws -> GTDConfig {
        throw NoteCodecError.notImplemented("T10: decodeConfig")
    }

    public static func decodeWeeklyReview(id: NoteID, text: String) throws -> WeeklyReview {
        throw NoteCodecError.notImplemented("T10: decodeWeeklyReview")
    }

    // MARK: - Encode

    public static func encode(_ item: InboxItem) -> String { unimplemented("encode(InboxItem)") }
    public static func encode(_ action: Action) -> String { unimplemented("encode(Action)") }
    public static func encode(_ area: Area) -> String { unimplemented("encode(Area)") }
    public static func encode(_ project: Project) -> String { unimplemented("encode(Project)") }
    public static func encode(_ routine: Routine) -> String { unimplemented("encode(Routine)") }
    public static func encode(_ config: GTDConfig) -> String { unimplemented("encode(GTDConfig)") }
    public static func encode(_ review: WeeklyReview) -> String { unimplemented("encode(WeeklyReview)") }

    /// All entries of one day/device log file.
    public static func encodeRoutineLog(_ entries: [RoutineLogEntry]) -> String {
        unimplemented("encodeRoutineLog")
    }

    private static func unimplemented(_ what: String) -> Never {
        fatalError("T10: \(what) is not implemented yet")
    }
}

public enum NoteCodecError: Error, Equatable {
    /// Placeholder while T10 is unwritten.
    case notImplemented(String)
    /// A file the app will not guess about — surfaces as a `VaultIssue` (N3 §7.5).
    case unreadable(path: String, reason: String)
}
