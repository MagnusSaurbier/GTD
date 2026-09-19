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

    @Test func fileNameIsTheLocalTimestamp() throws {
        let moment = try date("2026-09-19T08:12:04+00:00")
        #expect(InboxWriter.stamp(moment, calendar: utc) == "2026-09-19 081204")
        #expect(InboxWriter.stamp(moment, calendar: berlin) == "2026-09-19 101204")
    }

    @Test func createdIsIsoWithTheLocalOffset() throws {
        let moment = try date("2026-09-19T08:12:04+00:00")
        #expect(InboxWriter.iso(moment, calendar: utc) == "2026-09-19T08:12:04+00:00")
        #expect(InboxWriter.iso(moment, calendar: berlin) == "2026-09-19T10:12:04+02:00")
    }

    @Test func writesOneFileWithTheCreatedFrontmatter() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let id = try writer.capture(text: "buy running shoes", at: try date("2026-09-19T08:12:04+00:00"))

        #expect(id.path == "Inbox/2026-09-19 081204.md")
        #expect(try fs.readText(id.path) == """
        ---
        created: 2026-09-19T08:12:04+00:00
        ---
        buy running shoes

        """)
    }

    @Test func twoCapturesInTheSameSecondGetSuffixesAndNeverOverwrite() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let moment = try date("2026-09-19T08:12:04+00:00")

        let first = try writer.capture(text: "one", at: moment)
        let second = try writer.capture(text: "two", at: moment)
        let third = try writer.capture(text: "three", at: moment)

        #expect(first.path == "Inbox/2026-09-19 081204.md")
        #expect(second.path == "Inbox/2026-09-19 081204-1.md")
        #expect(third.path == "Inbox/2026-09-19 081204-2.md")
        #expect(try fs.readText(first.path)?.contains("one") == true)
        #expect(try fs.readText(second.path)?.contains("two") == true)
    }

    @Test func multiLineCapturesKeepTheirBodyAndEndWithExactlyOneNewline() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let id = try writer.capture(text: "line one\nline two\n\n\n",
                                    at: try date("2026-09-19T08:12:04+00:00"))
        let text = try #require(try fs.readText(id.path))
        #expect(text.hasSuffix("line one\nline two\n"))
    }

    @Test func honoursACustomInboxFolder() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, layout: VaultLayout(inbox: "00 Inbox"), calendar: utc)
        let id = try writer.capture(text: "x", at: try date("2026-09-19T08:12:04+00:00"))
        #expect(id.path == "00 Inbox/2026-09-19 081204.md")
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
        #expect(vault.read(id.path)?.contains("on disk") == true)
    }

    /// The writer renders its own frontmatter so capture needs neither the codec nor an index.
    /// This pins that format to the codec's the moment T10 lands.
    @Test(.enabled(if: NoteCodecParser.codecIsImplemented))
    func captureRoundTripsThroughTheCodec() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: utc)
        let moment = try date("2026-09-19T08:12:04+00:00")
        let id = try writer.capture(text: "buy running shoes", at: moment)
        let text = try #require(try fs.readText(id.path))

        let item = try NoteCodec.decodeInboxItem(id: id, text: text)
        #expect(item.text == "buy running shoes")
        #expect(abs(item.created.timeIntervalSince(moment)) < 1)
        #expect(item.reviewReason == nil)
        #expect(NoteCodec.encode(item) == text)
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
