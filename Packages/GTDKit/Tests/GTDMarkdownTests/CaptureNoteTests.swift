import Testing
import Foundation
import GTDModel
@testable import GTDMarkdown

/// The two schema-visible halves of the 2026-09-21 rework: **R-4**'s lead paragraph
/// (`Action.preamble` — the full capture text above `# Why?`) and **W1/D39**'s optional
/// `waitingFor:`. Both are patch-level behaviour, so they are asserted on the bytes.
struct CaptureNoteTests {

    private let id = NoteID(path: "Actions/Prüfungsanmeldung.md")

    private func action(_ status: ActionStatus = .next) -> Action {
        Action(id: id, title: id.title, status: status)
    }

    // MARK: - R-4: the paragraph above the headings

    @Test func aFreshNoteWritesTheCaptureTextAboveTheHeadings() throws {
        var fresh = action()
        fresh.preamble = "Prüfungsanmeldung für Mathe über das Portal, Frist ist der 30."
        fresh.why = "The registration window closes."
        fresh.what = "Log in and register."

        let text = NoteCodec.encode(fresh)
        #expect(text == """
        ---
        status: next
        ---
        Prüfungsanmeldung für Mathe über das Portal, Frist ist der 30.

        # Why?
        The registration window closes.

        # What?
        Log in and register.

        """)
        // …and it comes back as the same three pieces.
        let back = try NoteCodec.decodeAction(id: id, text: text)
        #expect(back.preamble == fresh.preamble)
        #expect(back.why == fresh.why)
        #expect(back.what == fresh.what)
    }

    @Test func aNoteWithoutALeadParagraphKeepsItsBodyUnchanged() throws {
        var fresh = action()
        fresh.why = "Because."
        fresh.what = "Do it."
        let text = NoteCodec.encode(fresh)
        #expect(!text.contains("\n\n\n"))
        #expect(try NoteCodec.decodeAction(id: id, text: text).preamble.isEmpty)
    }

    /// A headingless body is the `What?` (hand-written notes, promoted list items), so it is
    /// never read as a lead paragraph as well — that would duplicate it.
    @Test func aHeadinglessBodyIsTheWhatAndNotAPreamble() throws {
        let text = """
        ---
        status: someday
        ---
        Just a line somebody typed in Obsidian.

        """
        let decoded = try NoteCodec.decodeAction(id: id, text: text)
        #expect(decoded.preamble.isEmpty)
        #expect(decoded.what == "Just a line somebody typed in Obsidian.")
        #expect(NoteCodec.encode(decoded) == text)
    }

    @Test func editingOnlyTheLeadParagraphChangesOnlyThoseLines() throws {
        let original = """
        ---
        status: next
        tags: [uni]
        ---
        The whole dictation, as it was captured.

        # Why?
        Because.

        # What?
        Do it.

        """
        var decoded = try NoteCodec.decodeAction(id: id, text: original)
        #expect(decoded.preamble == "The whole dictation, as it was captured.")
        decoded.preamble = "The whole dictation, corrected."
        let encoded = NoteCodec.encode(decoded)
        #expect(encoded == original.replacingOccurrences(
            of: "The whole dictation, as it was captured.",
            with: "The whole dictation, corrected."))
    }

    // MARK: - W1/D39: `waitingFor:` is optional

    @Test func waitingWithoutAWhoWritesNoWaitingForLine() throws {
        var waiting = action(.waiting)
        waiting.what = "Wait for the office."
        waiting.followUpDate = Day(year: 2026, month: 9, day: 26)
        let text = NoteCodec.encode(waiting)
        #expect(text.contains("status: waiting"))
        #expect(text.contains("followUpDate: 2026-09-26"))
        #expect(!text.contains("waitingFor"))
        #expect(try NoteCodec.decodeAction(id: id, text: text).waiting
                == WaitingInfo(who: nil, followUp: Day(year: 2026, month: 9, day: 26)))
    }

    @Test func clearingTheWhoRemovesTheLineAndNothingElse() throws {
        let original = """
        ---
        status: waiting
        waitingFor: "Prof. Weber"
        followUpDate: 2026-09-26
        created: 2026-09-07T09:30:00+02:00
        ---
        # Why?
        Because.

        # What?
        Wait.

        """
        var decoded = try NoteCodec.decodeAction(id: id, text: original, timeZone: vaultTimeZone)
        decoded.waitingFor = nil
        let encoded = NoteCodec.encode(decoded, timeZone: vaultTimeZone)
        #expect(encoded == original.replacingOccurrences(
            of: "waitingFor: \"Prof. Weber\"\n", with: ""))
    }
}
