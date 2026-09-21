import Foundation
import GTDMarkdown
import GTDModel

/// The seam between the scanner and `GTDMarkdown.NoteCodec` (T10).
///
/// The store never calls `NoteCodec` directly: everything goes through this protocol, so the
/// index, the snapshot assembly and the transaction logic can be tested with a stub parser while
/// the codec is still being written, and so a decode failure has exactly one place to turn into
/// a `VaultIssue`.
public protocol VaultNoteParser: Sendable {
    func inboxItem(id: NoteID, text: String) throws -> InboxItem
    func action(id: NoteID, text: String) throws -> Action
    /// §5a — `layout` says where the lists root is; the list and the finished flag come from the
    /// path below it.
    func listItem(id: NoteID, text: String, layout: VaultLayout) throws -> ListItem
    func area(id: NoteID, text: String) throws -> Area
    func project(id: NoteID, text: String) throws -> Project
    func routine(id: NoteID, text: String) throws -> Routine
    func routineLog(id: NoteID, text: String) throws -> [RoutineLogEntry]
    func config(id: NoteID, text: String) throws -> GTDConfig
    func weeklyReview(id: NoteID, text: String) throws -> WeeklyReview
}

/// The production parser: a thin forward to `GTDMarkdown.NoteCodec`.
public struct NoteCodecParser: VaultNoteParser {
    public init() {}

    public func inboxItem(id: NoteID, text: String) throws -> InboxItem {
        try NoteCodec.decodeInboxItem(id: id, text: text)
    }

    public func action(id: NoteID, text: String) throws -> Action {
        try NoteCodec.decodeAction(id: id, text: text)
    }

    public func listItem(id: NoteID, text: String, layout: VaultLayout) throws -> ListItem {
        try NoteCodec.decodeListItem(id: id, text: text, layout: layout)
    }

    public func area(id: NoteID, text: String) throws -> Area {
        try NoteCodec.decodeArea(id: id, text: text)
    }

    public func project(id: NoteID, text: String) throws -> Project {
        try NoteCodec.decodeProject(id: id, text: text)
    }

    public func routine(id: NoteID, text: String) throws -> Routine {
        try NoteCodec.decodeRoutine(id: id, text: text)
    }

    public func routineLog(id: NoteID, text: String) throws -> [RoutineLogEntry] {
        try NoteCodec.decodeRoutineLog(id: id, text: text)
    }

    public func config(id: NoteID, text: String) throws -> GTDConfig {
        try NoteCodec.decodeConfig(id: id, text: text)
    }

    public func weeklyReview(id: NoteID, text: String) throws -> WeeklyReview {
        try NoteCodec.decodeWeeklyReview(id: id, text: text)
    }

    /// Whether T10's codec is implemented in this build.
    ///
    /// Until it lands every decode throws `NoteCodecError.notImplemented`, and a scan of a real
    /// vault would produce nothing but issues. The integration tests are gated on this, and
    /// `FileVaultStore` turns a `notImplemented` into one clearly-worded `VaultIssue` per file
    /// instead of pretending the note is corrupt.
    public static let codecIsImplemented: Bool = {
        let probe = "---\ncreated: 2026-01-01T00:00:00+01:00\n---\nprobe\n"
        do {
            _ = try NoteCodec.decodeInboxItem(id: NoteID(path: "Inbox/probe.md"), text: probe)
            return true
        } catch let error as NoteCodecError {
            if case .notImplemented = error { return false }
            return true
        } catch {
            return true
        }
    }()
}
