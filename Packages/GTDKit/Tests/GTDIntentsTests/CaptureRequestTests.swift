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
@Suite("CaptureRequest — normalisation, naming, routing to the inbox writer (C1, C3)")
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

    @Test func performWritesOneFileNamedAfterTheCapture() throws {
        let fs = InMemoryFileSystem()
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)
        let id = try CaptureRequest(text: "  buy running shoes ").perform(writer: fakeWriter(fs), now: moment)

        #expect(id.path == "Inbox/buy running shoes.md")
        #expect(try fs.readText(id.path)?.contains("created: 2026-09-19T08:12:04+02:00") == true)
    }

    @Test func twoCapturesWithTheSameNameGetCollisionSuffixesAndNeverOverwrite() throws {
        let fs = InMemoryFileSystem()
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)
        let writer = fakeWriter(fs)

        let first = try CaptureRequest(text: "call mum").perform(writer: writer, now: moment)
        let second = try CaptureRequest(text: "call mum\nabout Sunday").perform(writer: writer, now: moment)

        #expect(first.path == "Inbox/call mum.md")
        #expect(second.path == "Inbox/call mum 2.md")
        #expect(try fs.readText(second.path)?.contains("about Sunday") == true)
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

    /// A *saved but unusable* bookmark is a different problem from "you never picked a vault",
    /// and the two messages send the user to different places. `InboxWriter` used to ask
    /// `startAccess()` first, which returns a bare `false` either way and made
    /// `CaptureError.bookmarkStale` unreachable (T30 gotcha #1). T41 made it resolve first.
    @Test func aStaleBookmarkSurfacesAsBookmarkStaleNotNoVaultSelected() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gtd-intents-stale-bookmark-\(UUID().uuidString).data")
        try Data().write(to: file)   // present, but not resolvable to a folder
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = VaultBookmark(store: PathBookmarkStore(), fileURL: file)
        let writer = InboxWriter(bookmark: bookmark)

        #expect(throws: CaptureError.bookmarkStale) {
            _ = try CaptureRequest(text: "buy milk").perform(writer: writer)
        }
    }

    /// The third case: the folder resolves, but the sandbox refuses to open it. That is neither
    /// "no vault" nor "stale" — it is carried through verbatim so the user sees the real reason.
    @Test func aRefusedSecurityScopeIsReportedAsAWriteFailureNotAsAMissingVault() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gtd-intents-refused-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gtd-intents-refused-bookmark-\(UUID().uuidString).data")
        try Data(folder.path.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let bookmark = VaultBookmark(store: RefusingBookmarkStore(), fileURL: file)
        let writer = InboxWriter(bookmark: bookmark)

        do {
            _ = try CaptureRequest(text: "buy milk").perform(writer: writer)
            Issue.record("expected the refused scope to throw")
        } catch {
            guard case let .writeFailed(reason) = error else {
                Issue.record("expected .writeFailed, got \(error)")
                return
            }
            #expect(reason.contains("refused"))
        }
    }

    @Test func everyCaptureErrorHasANonEmptyMessage() {
        let errors: [CaptureError] = [.emptyText, .noVaultSelected, .bookmarkStale, .writeFailed("disk full")]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(CaptureError.writeFailed("disk full").errorDescription?.contains("disk full") == true)
    }

}

/// A bookmark store whose folder resolves but whose scoped access is refused — the sandbox
/// case `InboxWriter` must report as itself rather than as "no vault selected" (T41).
private struct RefusingBookmarkStore: BookmarkStore {
    func bookmarkData(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8), !path.isEmpty else {
            throw VaultError.bookmarkStale
        }
        return (URL(fileURLWithPath: path, isDirectory: true), false)
    }
    func startAccess(_ url: URL) -> Bool { false }
    func stopAccess(_ url: URL) {}
}
