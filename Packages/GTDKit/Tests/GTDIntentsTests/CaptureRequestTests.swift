import Foundation
import GTDFixtures
import GTDModel
import GTDVault
import Testing
@testable import GTDIntents

/// `CaptureRequest` is the logic behind `CaptureToInboxIntent`, tested here against a real
/// `InboxWriter` backed by `InMemoryFileSystem` — the "fake writer" the T30 brief asks for; it is
/// the only fake-able part of the pipeline (`InboxWriter` renders its own frontmatter, see its
/// doc comment).
@Suite("CaptureRequest — normalisation, stamping, routing to the inbox writer (C1, C3)")
struct CaptureRequestTests {

    private var berlin: Calendar { Fixtures.calendar }

    private func fakeWriter(_ fs: InMemoryFileSystem = InMemoryFileSystem()) -> InboxWriter {
        InboxWriter(fileSystem: fs, calendar: berlin)
    }

    // MARK: Normalisation

    @Test func rejectsEmptyOrWhitespaceOnlyText() {
        #expect(throws: CaptureError.emptyText) { try CaptureRequest(text: "").normalized() }
        #expect(throws: CaptureError.emptyText) { try CaptureRequest(text: "   \n\t ").normalized() }
    }

    @Test func trimsLeadingAndTrailingWhitespace() throws {
        #expect(try CaptureRequest(text: "  buy milk  ").normalized() == "buy milk")
        #expect(try CaptureRequest(text: "\nbuy milk\n\n").normalized() == "buy milk")
    }

    @Test func keepsInternalLineBreaks() throws {
        let normalized = try CaptureRequest(text: "  line one\nline two  ").normalized()
        #expect(normalized == "line one\nline two")
    }

    // MARK: perform() — file name format, collisions, empty rejection

    @Test func performWritesOneFileNamedByTheCaptureMoment() throws {
        let fs = InMemoryFileSystem()
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)
        let id = try CaptureRequest(text: "buy running shoes").perform(writer: fakeWriter(fs), now: moment)

        #expect(id.path == "Inbox/2026-09-19 081204.md")
        #expect(try fs.readText(id.path)?.contains("buy running shoes") == true)
    }

    @Test func twoCapturesInTheSameSecondGetCollisionSuffixesAndNeverOverwrite() throws {
        let fs = InMemoryFileSystem()
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)
        let writer = fakeWriter(fs)

        let first = try CaptureRequest(text: "one").perform(writer: writer, now: moment)
        let second = try CaptureRequest(text: "two").perform(writer: writer, now: moment)

        #expect(first.path == "Inbox/2026-09-19 081204.md")
        #expect(second.path == "Inbox/2026-09-19 081204-1.md")
        #expect(try fs.readText(first.path)?.contains("one") == true)
        #expect(try fs.readText(second.path)?.contains("two") == true)
    }

    @Test func multiLineCapturesKeepTheirBody() throws {
        let fs = InMemoryFileSystem()
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)
        let id = try CaptureRequest(text: "line one\nline two\n\n\n").perform(writer: fakeWriter(fs), now: moment)
        let text = try #require(try fs.readText(id.path))
        #expect(text.hasSuffix("line one\nline two\n"))
    }

    @Test func performRejectsEmptyTextBeforeTouchingTheWriter() throws {
        let fs = InMemoryFileSystem()
        #expect(throws: CaptureError.emptyText) {
            _ = try CaptureRequest(text: "   ").perform(writer: fakeWriter(fs))
        }
        #expect(try fs.listFiles().isEmpty)
    }

    // MARK: Error mapping (T30 acceptance: useful spoken/visible errors)

    @Test func noVaultSelectedIsMappedAndHasAMessage() throws {
        let bookmark = VaultBookmark(
            store: PathBookmarkStore(),
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("gtd-intents-no-such-bookmark-\(UUID().uuidString)"))
        let writer = InboxWriter(bookmark: bookmark)

        #expect(throws: CaptureError.noVaultSelected) {
            _ = try CaptureRequest(text: "buy milk").perform(writer: writer)
        }
        #expect(CaptureError.noVaultSelected.errorDescription?.isEmpty == false)
    }

    /// `VaultBookmark.startAccess()` calls `try? resolve()`, so a stale/corrupt bookmark and a
    /// never-picked one both come out of `InboxWriter.capture` as `VaultError.noVaultSelected` —
    /// there is currently no path through `InboxWriter` that produces `.bookmarkStale` (T30
    /// Result: gotcha for T40/T41). This pins that real, current behaviour rather than the
    /// aspirational one; `CaptureError.noVaultSelected`'s message is worded to cover both causes.
    @Test func aStaleBookmarkCurrentlySurfacesAsNoVaultSelectedToo() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gtd-intents-stale-bookmark-\(UUID().uuidString).data")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = VaultBookmark(store: PathBookmarkStore(), fileURL: file)
        let writer = InboxWriter(bookmark: bookmark)

        #expect(throws: CaptureError.noVaultSelected) {
            _ = try CaptureRequest(text: "buy milk").perform(writer: writer)
        }
    }

    @Test func everyCaptureErrorHasANonEmptyMessage() {
        let errors: [CaptureError] = [.emptyText, .noVaultSelected, .bookmarkStale, .writeFailed("disk full")]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(CaptureError.writeFailed("disk full").errorDescription?.contains("disk full") == true)
    }

    // MARK: CaptureStamp

    @Test func stampFormat() {
        #expect(CaptureStamp.string(for: Fixtures.date(Fixtures.today, 8, 12, 4), calendar: berlin)
                == "2026-09-19 081204")
    }
}
