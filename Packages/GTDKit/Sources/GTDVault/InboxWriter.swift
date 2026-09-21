import Foundation
import GTDModel

/// Standalone capture writer: one file in `Inbox/`, no index, no scan, no codec (C1, C3).
///
/// Capture must work in under three seconds from a Shortcut, with neither Obsidian nor the app
/// running (T30), so this type deliberately does the least possible: resolve the bookmark, build
/// `Inbox/<yyyy-MM-dd HHmmss>[-n].md`, write it atomically.
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

    @discardableResult
    public func capture(text: String, at date: Date = Date()) throws -> NoteID {
        let target = try resolveFileSystem()
        defer { if fileSystem == nil { bookmark.stopAccess() } }

        let stamp = InboxWriter.stamp(date, calendar: calendar)
        var id = layout.inboxPath(stamp: stamp)
        var collision = 0
        // Two captures in the same second (or a second device's file already synced in) get
        // `-1`, `-2`, … . Never overwrite: a capture is the one thing with no other copy.
        while target.exists(id.path) {
            collision += 1
            guard collision < 1000 else {
                throw VaultError.ioFailed(path: id.path, reason: "too many captures this second")
            }
            id = layout.inboxPath(stamp: stamp, collision: collision)
        }

        try target.writeText(InboxWriter.note(text: text, created: date, calendar: calendar),
                             to: id.path)
        return id
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

    /// `yyyy-MM-dd HHmmss` in the device's time zone — the capture file name (C3).
    static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day)) "
            + "\(pad(c.hour))\(pad(c.minute))\(pad(c.second))"
    }

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

    static func note(text: String, created: Date, calendar: Calendar = .current) -> String {
        var body = text
        while body.hasSuffix("\n") { body.removeLast() }
        return "---\ncreated: \(iso(created, calendar: calendar))\n---\n\(body)\n"
    }

    private static func pad(_ value: Int?, _ width: Int = 2) -> String {
        let s = String(value ?? 0)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}
