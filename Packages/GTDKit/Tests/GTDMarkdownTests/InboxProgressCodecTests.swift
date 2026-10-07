import Testing
import Foundation
import GTDModel
@testable import GTDMarkdown

/// #85 — a half-processed card kept in its inbox note: the chips under the action keys, read
/// back and written with one changed line per changed value, and a note that has them still
/// round-trips byte for byte.
struct InboxProgressCodecTests {
    private let id = NoteID(path: "Inbox/call the Hausverwaltung.md")
    private let text = """
        ---
        created: 2026-09-08T07:12:33+02:00
        contexts: [calls, mac]
        timeEstimate: 30
        project: "[[Projects/no_area/Flat/Flat]]"
        defer: 2026-10-06
        due: 2026-10-09
        ---
        capture text

        # Why?
        because

        # What?
        call

        """

    @Test func theChipsAreRead() throws {
        let item = try NoteCodec.decodeInboxItem(id: id, text: text, timeZone: vaultTimeZone)
        #expect(item.contexts == ["calls", "mac"])
        #expect(item.timeEstimate == 30)
        #expect(item.project == NoteID(path: "Projects/no_area/Flat/Flat.md"))
        #expect(item.deferDate == Day(year: 2026, month: 10, day: 6))
        #expect(item.due == Day(year: 2026, month: 10, day: 9))
        #expect(InboxBody.read(item.body) == InboxBody(lead: "capture text", why: "because", what: "call"))
    }

    @Test func aNoteWithProgressRoundTrips() throws {
        #expect(try RoundTrip.encodeDecoded(path: id.path, text: text) == text)
    }

    @Test func savingProgressIntoAPlainCaptureAddsTheKeys() throws {
        let plain = "---\ncreated: 2026-09-08T07:12:33+02:00\n---\ncapture text\n"
        var item = try NoteCodec.decodeInboxItem(id: id, text: plain, timeZone: vaultTimeZone)
        item.contexts = ["calls"]
        item.timeEstimate = 10
        item.body = InboxBody(lead: "capture text", why: "because").written(over: item.body)

        let encoded = NoteCodec.encode(item, timeZone: vaultTimeZone)
        #expect(encoded == """
            ---
            created: 2026-09-08T07:12:33+02:00
            contexts: [calls]
            timeEstimate: 10
            ---
            capture text

            # Why?
            because

            """)
        let back = try NoteCodec.decodeInboxItem(id: id, text: encoded, timeZone: vaultTimeZone)
        #expect(back.progress == item.progress)
    }

    @Test func clearingTheChipsRemovesTheKeysAndNothingElse() throws {
        var item = try NoteCodec.decodeInboxItem(id: id, text: text, timeZone: vaultTimeZone)
        item.contexts = []
        item.timeEstimate = nil
        item.project = nil
        item.deferDate = nil
        item.due = nil
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone) == """
            ---
            created: 2026-09-08T07:12:33+02:00
            ---
            capture text

            # Why?
            because

            # What?
            call

            """)
    }
}
