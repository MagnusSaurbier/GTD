import Foundation
import GTDMarkdown
import GTDModel
import Testing
@testable import GTDVault

@Suite("InboxWriter — capture without the vault loaded (C1, C3)")
struct InboxWriterTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7200) ?? .gmt
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try #require(StubNoteParser.date(iso))
    }

    @Test func createdIsIsoWithTheLocalOffset() throws {
        let moment = try date("2026-09-19T08:12:04+00:00")
        #expect(InboxWriter.iso(moment, calendar: utc) == "2026-09-19T08:12:04+00:00")
        #expect(InboxWriter.iso(moment, calendar: berlin) == "2026-09-19T10:12:04+02:00")
    }

    /// C3 (2026-09-22) — a capture is named after its text; a title that carries the whole
    /// text leaves the body empty, so nothing is written below the frontmatter.
    @Test func theFileIsNamedAfterTheCaptureAndTheBodyStaysEmpty() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let id = try writer.capture(text: "buy running shoes", at: try date("2026-09-19T08:12:04+00:00"))

        #expect(id.path == "Inbox/buy running shoes.md")
        #expect(id.title == "buy running shoes")
        #expect(try fs.readText(id.path) == """
        ---
        created: 2026-09-19T08:12:04+00:00
        ---

        """)
    }

    /// The title is the first line, sanitised and cut; the body keeps the full text because the
    /// title could not carry it (R-4).
    @Test func aLongOrMultiLineCaptureKeepsItsFullTextInTheBody() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let id = try writer.capture(text: "idea: rename the scans\nby their date\n\n\n",
                                    at: try date("2026-09-19T08:12:04+00:00"))
        #expect(id.path == "Inbox/idea rename the scans.md")
        let text = try #require(try fs.readText(id.path))
        #expect(text.hasSuffix("---\nidea: rename the scans\nby their date\n"))
    }

    @Test func aTakenNameGetsANumberAndNothingIsOverwritten() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let moment = try date("2026-09-19T08:12:04+00:00")

        let first = try writer.capture(text: "call mum", at: moment)
        let second = try writer.capture(text: "call mum", at: moment)
        let third = try writer.capture(text: "call mum\nabout Sunday", at: moment)

        #expect(first.path == "Inbox/call mum.md")
        #expect(second.path == "Inbox/call mum 2.md")
        #expect(third.path == "Inbox/call mum 3.md")
        #expect(try fs.readText(third.path)?.contains("about Sunday") == true)
        #expect(try fs.listFiles().count == 3)
    }

    /// An evicted iCloud file exists only as its `.<name>.icloud` placeholder. Its name is still
    /// taken: writing over it would make iCloud produce a conflict copy.
    @Test func anEvictedNoteStillTakesItsName() throws {
        let vault = try TempVault()
        try vault.write("", to: "Inbox/.call mum.md.icloud")
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: vault.url), calendar: utc)
        let id = try writer.capture(text: "call mum", at: try date("2026-09-19T08:12:04+00:00"))
        #expect(id.path == "Inbox/call mum 2.md")
    }

    /// No timestamp fallback: an empty capture has nothing to name the note after, so it is
    /// refused — before the vault is even resolved.
    @Test(arguments: ["", "   ", "\n\n \t\n"])
    func anEmptyCaptureIsRefused(_ text: String) throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        #expect(throws: InboxWriter.CaptureRefusal.empty) {
            try writer.capture(text: text, at: try date("2026-09-19T08:12:04+00:00"))
        }
        #expect(try fs.listFiles().isEmpty)
    }

    @Test func honoursACustomInboxFolder() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, layout: VaultLayout(inbox: "00 Inbox"), calendar: utc)
        let id = try writer.capture(text: "x", at: try date("2026-09-19T08:12:04+00:00"))
        #expect(id.path == "00 Inbox/x.md")
    }

    @Test func capturingWithoutAVaultFails() throws {
        let bookmark = VaultBookmark(
            store: PathBookmarkStore(),
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("gtd-no-such-bookmark-\(UUID().uuidString)"))
        let writer = InboxWriter(bookmark: bookmark)
        #expect(throws: VaultError.noVaultSelected) { try writer.capture(text: "x", at: Date()) }
    }

    @Test func worksAgainstARealDirectory() throws {
        let vault = try TempVault()
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: vault.url), calendar: utc)
        let id = try writer.capture(text: "on disk", at: try date("2026-09-19T08:12:04+00:00"))
        #expect(id.path == "Inbox/on disk.md")
        #expect(vault.read(id.path)?.hasPrefix("---\ncreated: ") == true)
    }

    /// The writer renders its own frontmatter so capture needs neither the codec nor an index.
    /// This pins that format to the codec's — with and without a body.
    @Test(.enabled(if: NoteCodecParser.codecIsImplemented),
          arguments: ["buy running shoes", "buy running shoes\nthe blue ones"])
    func captureRoundTripsThroughTheCodec(_ capture: String) throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let moment = try date("2026-09-19T08:12:04+00:00")
        let id = try writer.capture(text: capture, at: moment)
        let text = try #require(try fs.readText(id.path))

        let item = try NoteCodec.decodeInboxItem(id: id, text: text)
        #expect(item.title == "buy running shoes")
        #expect(item.body == (capture.contains("\n") ? capture : ""))
        #expect(abs(item.created.timeIntervalSince(moment)) < 1)
        #expect(item.reviewReason == nil)
        #expect(NoteCodec.encode(item) == text)
        // A fresh item with the same fields renders the very same bytes (N2 from scratch).
        let fresh = InboxItem(id: id, body: item.body, created: item.created)
        #expect(NoteCodec.encode(fresh, timeZone: utc.timeZone) == text)
    }
}

@Suite("VaultBookmark")
struct VaultBookmarkTests {

    private func bookmark() throws -> (VaultBookmark, URL) {
        let file = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gtd-bookmark-\(UUID().uuidString).data")
        return (VaultBookmark(store: PathBookmarkStore(), fileURL: file), file)
    }

    @Test func savesAndResolvesThePickedFolder() throws {
        let vault = try TempVault()
        let (mark, file) = try bookmark()
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(!mark.hasSavedVault)
        try mark.save(url: vault.url)
        #expect(mark.hasSavedVault)
        #expect(try mark.resolve().standardizedFileURL == vault.url.standardizedFileURL)
    }

    @Test func resolvingWithoutAPickedFolderReportsNoVault() throws {
        let (mark, _) = try bookmark()
        #expect(throws: VaultError.noVaultSelected) { try mark.resolve() }
    }

    @Test func accessIsBracketedAndClearingForgetsTheVault() throws {
        let vault = try TempVault()
        let (mark, file) = try bookmark()
        defer { try? FileManager.default.removeItem(at: file) }

        try mark.save(url: vault.url)
        #expect(mark.startAccess())
        mark.stopAccess()

        try mark.clear()
        #expect(!mark.hasSavedVault)
        #expect(!mark.startAccess())
    }

    @Test func savingOpensTheScopeOfAPickedFolderBeforeBookmarkingIt() throws {
        // What `.fileImporter` hands over on a Mac: bookmarking it outside
        // start/stopAccessing fails with "Could not open() the item" (Gate 3, first real run).
        let store = ScopedBookmarkStore()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtd-bookmark-\(UUID().uuidString).data")
        defer { try? FileManager.default.removeItem(at: file) }

        try VaultBookmark(store: store, fileURL: file).save(url: URL(fileURLWithPath: "/picked"))
        #expect(store.log.events == ["start", "bookmark", "stop"])
    }

    @Test func aCorruptBookmarkIsReportedAsStale() throws {
        let (mark, file) = try bookmark()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        #expect(throws: VaultError.bookmarkStale) { try mark.resolve() }
    }

    @Test func theBookmarkLivesOutsideTheVault() throws {
        // ARCHITECTURE §3: device-local state belongs in Application Support, never in the vault.
        let url = VaultBookmark.defaultFileURL()
        #expect(url.lastPathComponent == "vault-bookmark.data")
        #expect(url.deletingLastPathComponent().lastPathComponent == "GTD")
    }
}

/// Refuses to bookmark unless the URL's scope is open, and records the order of calls.
private struct ScopedBookmarkStore: BookmarkStore {
    final class Log: @unchecked Sendable {   // test-only; every call is on the test's one thread
        var events: [String] = []
        var isOpen = false
    }
    let log = Log()

    func bookmarkData(for url: URL) throws -> Data {
        guard log.isOpen else { throw VaultError.ioFailed(path: url.path, reason: "scope closed") }
        log.events.append("bookmark")
        return Data(url.path.utf8)
    }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
    func startAccess(_ url: URL) -> Bool {
        log.events.append("start"); log.isOpen = true; return true
    }
    func stopAccess(_ url: URL) {
        log.events.append("stop"); log.isOpen = false
    }
}
