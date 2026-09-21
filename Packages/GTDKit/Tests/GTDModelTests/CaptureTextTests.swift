import Testing
import Foundation
import GTDModel

/// R-4 — the capture text becomes a file name and a note body. `Reducer` applies these rules
/// (`ReducerInboxTests` covers that); this is the table behind them.
struct CaptureTextTests {

    @Test func aShortCaptureIsItsOwnTitle() {
        #expect(CaptureText.title(of: "call the Hausverwaltung") == "call the Hausverwaltung")
        #expect(!CaptureText.carriesMore("call the Hausverwaltung", than: "call the Hausverwaltung"))
        #expect(CaptureText.body(capture: "call the Hausverwaltung",
                                 title: "call the Hausverwaltung", notes: "") == "")
    }

    /// Characters, not bytes: 60 umlauts are 60 characters and fit.
    @Test func theLimitCountsCharacters() {
        let sixty = String(repeating: "ü", count: 60)
        #expect(CaptureText.title(of: sixty) == sixty)
        #expect(CaptureText.title(of: sixty)?.count == 60)
        let sixtyOne = String(repeating: "ü", count: 61)
        // One word, nowhere to cut: the file name still has to end somewhere.
        #expect(CaptureText.title(of: sixtyOne)?.count == 60)
        #expect(CaptureText.carriesMore(sixtyOne, than: CaptureText.title(of: sixtyOne) ?? ""))
    }

    @Test func aLongDictationIsCutAtAWordBoundary() throws {
        let text = "Beim Studierendenwerk nachfragen, ob die Kaution für das Zimmer schon da ist"
        let title = try #require(CaptureText.title(of: text))
        #expect(title == "Beim Studierendenwerk nachfragen, ob die Kaution für das")
        #expect(title.count <= CaptureText.titleLimit)
        #expect(text.hasPrefix(title))
        #expect(!title.hasSuffix(" "))
        #expect(CaptureText.body(capture: text, title: title, notes: "") == text)
    }

    @Test func onlyTheFirstLineBecomesTheTitle() {
        #expect(CaptureText.title(of: "\n\n  Mail an den Vermieter\nKaution\nNebenkosten")
                == "Mail an den Vermieter")
        #expect(CaptureText.body(
            capture: "Mail an den Vermieter\nKaution",
            title: "Mail an den Vermieter",
            notes: "") == "Mail an den Vermieter\nKaution")
    }

    /// A title is a file name (A1), so it is sanitised — and a capture the sanitiser changed is
    /// kept in full in the body.
    @Test func theTitleIsSanitisedAndWhatItLosesStaysInTheBody() {
        #expect(CaptureText.title(of: "Read [[Buch]]: Kapitel 3") == "Read Buch Kapitel 3")
        #expect(CaptureText.body(
            capture: "Read [[Buch]]: Kapitel 3", title: "Read Buch Kapitel 3", notes: "")
            == "Read [[Buch]]: Kapitel 3")
    }

    @Test func onlyWhitespaceHasNoTitle() {
        #expect(CaptureText.title(of: "") == nil)
        #expect(CaptureText.title(of: "   \n\t ") == nil)
        // A capture of punctuation alone is *not* whitespace: it keeps `VaultLayout.sanitize`'s
        // fallback name, exactly as every other title in the app does — and because the title
        // then says less than the capture, the capture itself is kept in the body.
        #expect(CaptureText.title(of: "///") == "Untitled")
        #expect(CaptureText.body(capture: "///", title: "Untitled", notes: "") == "///")
    }

    @Test func theNotesPanelGoesBelowTheCaptureText() {
        let text = "Der Artikel über Wohnungsmärkte, den Marie in der Gruppe geteilt hat, gestern"
        let title = CaptureText.title(of: text) ?? ""
        #expect(CaptureText.body(capture: text, title: title, notes: "Vor Montag lesen")
                == text + "\n\nVor Montag lesen")
        // Nothing to keep: the notes stand alone, with no stray blank lines.
        #expect(CaptureText.body(capture: "Sapiens", title: "Sapiens", notes: "  Marie's copy ")
                == "Marie's copy")
    }
}
