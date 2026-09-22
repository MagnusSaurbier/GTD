import Foundation
import GTDFixtures
import GTDMarkdown
import GTDModel
import GTDVault
import Testing
@testable import GTDIntents

/// Whether T10's codec is implemented in this build — a local probe (not
/// `GTDVault.NoteCodecParser.codecIsImplemented`, which this test target does not depend on) so
/// these tests turn themselves on the moment T10 lands, exactly like `GTDVaultTests`'.
private let codecIsImplemented: Bool = {
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

/// T30 acceptance: "Files produced by both paths decode with `NoteCodec.decodeInboxItem`."
@Suite("Capture output decodes with NoteCodec (T30 acceptance)", .enabled(if: codecIsImplemented))
struct CaptureCodecRoundTripTests {

    @Test func aCaptureFromTheAppIntentPathDecodesCleanly() throws {
        let fs = InMemoryFileSystem()
        let writer = InboxWriter(fileSystem: fs, calendar: Fixtures.calendar)
        let moment = Fixtures.date(Fixtures.today, 8, 12, 4)

        let id = try CaptureRequest(text: "  buy running shoes  ").perform(writer: writer, now: moment)
        let text = try #require(try fs.readText(id.path))

        let item = try NoteCodec.decodeInboxItem(id: id, text: text)
        #expect(id.path == "Inbox/buy running shoes.md")
        #expect(item.title == "buy running shoes")
        #expect(item.body.isEmpty, "the title carries the whole capture")
        #expect(abs(item.created.timeIntervalSince(moment)) < 1)
        #expect(item.reviewReason == nil)
        #expect(NoteCodec.encode(item) == text)
    }

    /// Pins `Shortcuts/README.md`'s literal capture template (Deliverable A — the pure Shortcut
    /// recipe, which never runs through `InboxWriter`) to the same codec.
    @Test func theShortcutRecipesTemplateDecodesCleanly() throws {
        let text = """
        ---
        created: 2026-09-19T08:12:04+02:00
        ---
        buy running shoes
        """ + "\n"

        let item = try NoteCodec.decodeInboxItem(id: NoteID(path: "Inbox/2026-09-19 081204.md"), text: text)
        #expect(item.body == "buy running shoes")
        #expect(item.reviewReason == nil)
    }

    /// The Shortcut's "Format Date" ISO 8601 preset may render UTC as `Z` instead of `+00:00` —
    /// the codec must accept both, since a Shortcut author cannot force one or the other.
    @Test func aZuluOffsetFromTheShortcutsIso8601PresetAlsoDecodes() throws {
        let text = "---\ncreated: 2026-09-19T06:12:04Z\n---\nbuy running shoes\n"
        let item = try NoteCodec.decodeInboxItem(id: NoteID(path: "Inbox/2026-09-19 081204.md"), text: text)
        #expect(item.body == "buy running shoes")
    }
}
