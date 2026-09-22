import Foundation
import GTDModel

/// Standalone capture writer: one file in `Inbox/`, no index, no scan, no codec (C1, C3).
///
/// Capture must work in under three seconds from a Shortcut, with neither Obsidian nor the app
/// running (T30), so this type deliberately does the least possible: resolve the bookmark, name
/// the note after its text (`Inbox/<title>[ n].md`, `CaptureText.note(for:)`), write it
/// atomically. An empty capture is refused with `InboxWriter.CaptureRefusal.empty` — it is never
/// saved under a made-up name.
///
/// It renders its own two-key frontmatter rather than calling `NoteCodec.encode`. A fresh
/// capture has no unknown keys and no body sections to preserve, so there is nothing for the
/// round-trip rule (N2) to protect — and the writer stays usable when nothing else is loaded.
/// `InboxWriterTests.captureRoundTripsThroughTheCodec` pins the format to the codec's, so the two
/// writers cannot drift apart.
public struct InboxWriter: Sendable {
    public var layout: VaultLayout
    public var bookmark: VaultBookmark
    /// Injected by tests and by the store; `nil` means "resolve the bookmark on every capture".
    private let fileSystem: (any VaultFileSystem)?
    private let calendar: Calendar

    /// Why a capture was not written although the vault was reachable.
    public enum CaptureRefusal: Error, Equatable, Sendable {
        /// The text was empty or only whitespace, so there is nothing to name the note after.
        case empty
    }

    public init(layout: VaultLayout = .default, bookmark: VaultBookmark = VaultBookmark()) {
        self.layout = layout
        self.bookmark = bookmark
        self.fileSystem = nil
        self.calendar = .current
    }

    /// Writes straight into a file system that is already available (tests, and the app once the
    /// vault is open).
    public init(
        fileSystem: any VaultFileSystem,
        layout: VaultLayout = .default,
        calendar: Calendar = .current
    ) {
        self.layout = layout
        self.bookmark = VaultBookmark(store: PathBookmarkStore(),
                                      fileURL: URL(fileURLWithPath: "/dev/null"))
        self.fileSystem = fileSystem
        self.calendar = calendar
    }

    /// Writes `Inbox/<title>.md` and returns its id. The title is the first line of `text`
    /// (`CaptureText.title`); the body holds the full text only when the title could not carry it.
    /// A name that is taken gets ` 2`, ` 3`, … — never an overwrite: a capture is the one thing
    /// with no other copy.
    @discardableResult
    public func capture(text: String, at date: Date = Date()) throws -> NoteID {
        // Refused before the vault is touched: an empty capture needs no bookmark to fail.
        guard let note = CaptureText.note(for: text) else { throw CaptureRefusal.empty }
        let target = try resolveFileSystem()
        defer { if fileSystem == nil { bookmark.stopAccess() } }

        var id = layout.inboxPath(title: note.title)
        var collision = 1
        while InboxWriter.isTaken(id.path, in: target) {
            collision += 1
            guard collision < 1000 else {
                throw VaultError.ioFailed(path: id.path, reason: "too many captures with this name")
            }
            id = layout.inboxPath(title: note.title, collision: collision)
        }

        try target.writeText(InboxWriter.note(body: note.body, created: date, calendar: calendar),
                             to: id.path)
        return id
    }

    /// A name is taken by a file, and also by an evicted iCloud file that only exists as its
    /// `.<name>.icloud` placeholder (`info` reports those) — writing over that would make iCloud
    /// produce a conflict copy of a note the user never touched.
    private static func isTaken(_ path: String, in fileSystem: any VaultFileSystem) -> Bool {
        if fileSystem.exists(path) { return true }
        return ((try? fileSystem.info(path)) ?? nil) != nil
    }

    /// Resolve **first**, then bracket access.
    ///
    /// `startAccess()` returns a bare `false` for every failure, so asking it first folded
    /// "no vault has ever been picked" and "the saved bookmark no longer resolves" into one
    /// `noVaultSelected` — which is what made `GTDIntents.CaptureError.bookmarkStale`
    /// unreachable (T30 gotcha #1, fixed in T41). `resolve()` already tells the two apart, and
    /// a refusal *after* a successful resolve is a third thing again: the folder is known but
    /// the sandbox would not open it.
    private func resolveFileSystem() throws -> any VaultFileSystem {
        if let fileSystem { return fileSystem }
        let root = try bookmark.resolve()
        guard bookmark.startAccess() else {
            throw VaultError.ioFailed(
                path: root.path, reason: "the system refused access to the vault folder")
        }
        return VaultPlatform.makeFileSystem(root: root)
    }

    // MARK: Format (ARCHITECTURE §3)

    /// ISO-8601 with the device's UTC offset. Written by hand so the output does not depend on
    /// locale or platform (the same reason `GTDModel.Day` avoids `DateFormatter`).
    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = calendar.timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))T"
            + "\(pad(c.hour)):\(pad(c.minute)):\(pad(c.second))"
            + "\(sign)\(pad(minutes / 60)):\(pad(minutes % 60))"
    }

    /// The file: `created` and the body — nothing below the frontmatter when the body is empty,
    /// exactly what `NoteCodec.encode` renders for the same item.
    static func note(body: String, created: Date, calendar: Calendar = .current) -> String {
        var body = body
        while body.hasSuffix("\n") { body.removeLast() }
        let frontmatter = "---\ncreated: \(iso(created, calendar: calendar))\n---\n"
        return body.isEmpty ? frontmatter : frontmatter + body + "\n"
    }

    private static func pad(_ value: Int?, _ width: Int = 2) -> String {
        let s = String(value ?? 0)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}
