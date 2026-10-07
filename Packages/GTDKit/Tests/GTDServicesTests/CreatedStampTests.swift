import Foundation
import GTDFixtures
import GTDMarkdown
import GTDModel
import GTDServices
import GTDVault
import Testing

/// #89 — a capture without `created` is dated by its birth time, and the app's **first write**
/// of it stamps that date into the frontmatter. It has to be then: every app save replaces the
/// file atomically, which gives it a new birth time, so a date not written at that moment is
/// gone. Reading alone never writes (the vault is written only on item actions).
struct CreatedStampTests {
    private let born = Date(timeIntervalSince1970: 1_790_000_000)
    private let edited = Date(timeIntervalSince1970: 1_790_086_400)
    private let path = "Inbox/buy running shoes.md"

    private func vault() async throws -> TestVault {
        var files = SampleVault.files
        files[path] = "buy running shoes\n"
        let vault = TestVault.inMemory(files: files)
        let memory = try #require(vault.fileSystem as? InMemoryFileSystem)
        memory.setDates(of: path, created: born, modified: edited)
        try await vault.backend.start()
        return vault
    }

    @Test func readingDoesNotWriteTheNote() async throws {
        let vault = try await vault()
        defer { vault.cleanUp() }
        let item = try #require(await vault.backend.currentSnapshot().inbox.first { $0.id.path == path })
        #expect(item.created == born)
        #expect(try vault.text(path) == "buy running shoes\n")
    }

    /// The created-less file passes the stale-write guard (its bytes are what the snapshot was
    /// read from), and the write that follows carries the birth time as `created`.
    @Test func theFirstEditStampsTheBirthTime() async throws {
        let vault = try await vault()
        defer { vault.cleanUp() }
        _ = try await vault.backend.perform(.editInboxBody(NoteID(path: path), "size 44"))

        let text = try #require(try vault.text(path))
        #expect(text.hasPrefix("---\ncreated: "), "stamped: \(text)")
        #expect(text.contains("size 44"))
        let reread = try #require(try vault.rescan().inbox.first { $0.id.path == path })
        #expect(reread.created == born, "the stamp survives the file's new birth time")
    }

    /// A rename is a move — the file keeps its birth time and nothing is rewritten — so the
    /// date is still there for the first real write after it.
    @Test func aRenameKeepsTheBirthTimeForTheFirstWrite() async throws {
        let vault = try await vault()
        defer { vault.cleanUp() }
        _ = try await vault.backend.perform(.renameInboxItem(NoteID(path: path), title: "running shoes"))
        let renamed = "Inbox/running shoes.md"
        #expect(try vault.text(renamed) == "buy running shoes\n")

        _ = try await vault.backend.perform(.editInboxBody(NoteID(path: renamed), "size 44"))
        let reread = try #require(try vault.rescan().inbox.first { $0.id.path == renamed })
        #expect(reread.created == born)
    }

    /// Processing turns the capture into an action note; the action keeps the capture's date.
    @Test func processingCarriesTheBirthTimeIntoTheAction() async throws {
        let vault = try await vault()
        defer { vault.cleanUp() }
        _ = try await vault.backend.perform(.fileInbox(NoteID(path: path), .action(ActionDraft(
            title: "buy running shoes", status: .next, contexts: ["errands"], timeEstimate: 30,
            why: "The old ones are through.", what: "Buy running shoes."))))

        let action = try #require(try vault.rescan().actions.first { $0.title == "buy running shoes" })
        #expect(action.created == born)
        let text = try #require(try vault.text(action.id.path))
        #expect(text.contains("created: "))
    }
}
