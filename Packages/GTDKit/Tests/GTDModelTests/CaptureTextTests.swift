import Testing
import Foundation
import GTDModel

/// R-4 — the capture text becomes a file name and a note body. `Reducer` applies these rules
/// (`ReducerInboxTests` covers that); this is the table behind them.
struct CaptureTextTests {

    @Test func aCaptureOfOnlyStrippedSymbolsHasNoTitle() {
        // Not "Untitled": an empty capture is refused, not given a made-up name.
        #expect(CaptureText.title(of: "###") == nil)
        #expect(CaptureText.title(of: "  [[]] \n") == nil)
        #expect(CaptureText.renamedTitle("#") == nil)
        #expect(CaptureText.title(of: "# buy milk") == "buy milk")
    }

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
        // Punctuation the sanitiser strips leaves no name either: refused, never "Untitled"
        // (2026-09-22 — the file name is the title, and there is no fallback name).
        #expect(CaptureText.title(of: "///") == nil)
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

    // MARK: - Capture (C3, 2026-09-22)

    @Test func aCaptureIsNamedAfterItsTextAndKeepsABodyOnlyWhenNeeded() throws {
        let short = try #require(CaptureText.note(for: "  buy milk \n"))
        #expect(short.title == "buy milk")
        #expect(short.body == "")

        let multi = try #require(CaptureText.note(for: "\nbuy milk\nthe oat one"))
        #expect(multi.title == "buy milk")
        #expect(multi.body == "buy milk\nthe oat one")

        let sanitised = try #require(CaptureText.note(for: "idea: rename scans"))
        #expect(sanitised.title == "idea rename scans")
        #expect(sanitised.body == "idea: rename scans")
    }

    /// No timestamp fallback: there is no name for an empty capture, so there is no note.
    @Test(arguments: ["", " ", "\n\t\n  "])
    func anEmptyCaptureHasNoNote(_ text: String) {
        #expect(CaptureText.note(for: text) == nil)
    }

    @Test func aRenamedTitleJoinsItsLinesAndIsCutLikeACapture() {
        #expect(CaptureText.renamedTitle("call\nmum") == "call mum")
        #expect(CaptureText.renamedTitle("  a: b  ") == "a b")
        #expect(CaptureText.renamedTitle(String(repeating: "word ", count: 20))?.count ?? 99 <= 60)
        #expect(CaptureText.renamedTitle(" \n ") == nil)
    }

    // MARK: - The template skeleton (2026-09-22)

    /// The body of a note made in Obsidian from the user's template, exactly as found in the
    /// vault (`Inbox/note.md`, `Inbox/test task.md`), and the shapes it takes after editing.
    @Test(arguments: [
        "# Why?\n- \n\n# What?\n- [ ] ",
        "# Why?\n-\n\n# What?\n- [ ]\n",
        "# Why?\r\n- \r\n\r\n# What?\r\n- [ ] \r\n",
        "## why?\n* \n\n### WHAT?\n+ [ ]",
        "# What?\n- [ ]\n- [ ]\n",
        "",
        "  \n\n",
    ])
    func theEmptySkeletonIsAnEmptyBody(_ body: String) {
        #expect(CaptureText.isEmptyBody(body))
        #expect(CaptureText.content(ofBody: body) == "")
        #expect(CaptureText.filedBody(body: body, notes: "") == "")
        #expect(CaptureText.filedBody(body: body, notes: " Marie ") == "Marie")
    }

    @Test(arguments: [
        "# Why?\n- because\n\n# What?\n- [ ] ",
        "# Why?\n- \n\n# What?\n- [ ] call her",
        "# Why?\n- \n\n# What?\n- [x] ",
        "# Why?\n- \n\n# Notes\n",
        "#tag",
        "- [ ] \nsome words",
        "buy milk",
    ])
    func anythingTheUserWroteIsContent(_ body: String) {
        #expect(!CaptureText.isEmptyBody(body))
        #expect(CaptureText.content(ofBody: body) == body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func aFiledBodyPutsTheItemsBodyAboveTheNotes() {
        #expect(CaptureText.filedBody(body: "\nbuy milk\n", notes: "\nthe oat one\n")
                == "buy milk\n\nthe oat one")
        #expect(CaptureText.filedBody(body: "buy milk", notes: "  ") == "buy milk")
    }
}
