import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// §5a — the list-item note: the title is the file name, `created` is the only key the app
/// writes, the body is free notes, and everything else survives byte for byte (N2).
struct ListItemCodecTests {

    private let openID = NoteID(path: "Lists/Read/Sapiens.md")
    private let doneID = NoteID(path: "Lists/Read/Done/Sapiens.md")

    // MARK: - Decoding

    @Test func theFileNameIsTheTitleAndTheFolderIsTheList() throws {
        let item = try NoteCodec.decodeListItem(
            id: openID,
            text: "---\ncreated: 2026-09-01T09:30:00+02:00\n---\nMarie's copy.\n",
            timeZone: vaultTimeZone)
        #expect(item.title == "Sapiens")
        #expect(item.list == "Read")
        #expect(item.isFinished == false)
        #expect(item.notes == "Marie's copy.")
        #expect(item.created != nil)
    }

    /// L3 — `Done/` is the only thing that says an item is finished. There is no `status`.
    @Test func anItemInDoneIsFinished() throws {
        let item = try NoteCodec.decodeListItem(id: doneID, text: "---\n---\n")
        #expect(item.isFinished)
        #expect(item.list == "Read")
    }

    /// L1 — a list item carries no commitment, so a note with no frontmatter at all is a
    /// perfectly good one. Nothing is required, nothing is invented.
    @Test func aNoteWithoutFrontmatterIsAValidItem() throws {
        let item = try NoteCodec.decodeListItem(id: openID, text: "Just a line about the book.\n")
        #expect(item.created == nil)
        #expect(item.notes == "Just a line about the book.")
    }

    @Test(arguments: [
        "Lists/Sapiens.md",                       // not in any list
        "Lists/Read/Notes/Sapiens.md",            // nested deeper than a list holds
        "Lists/Done/Sapiens.md",                  // `Done` is reserved, not a list
        "Actions/Sapiens.md",                     // not under `Lists/` at all
    ])
    func aNoteThatIsNotInAListIsRefused(path: String) {
        #expect(throws: NoteCodecError.self) {
            _ = try NoteCodec.decodeListItem(id: NoteID(path: path), text: "---\n---\n")
        }
    }

    // MARK: - Round trip (N2)

    static let items: [(name: String, text: String)] = [
        ("created and notes", "---\ncreated: 2026-09-01T09:30:00+02:00\n---\nMarie's copy.\n"),
        ("no frontmatter at all", "A plain note, nothing else.\n"),
        ("empty frontmatter, no body", "---\n---\n"),
        ("no body", "---\ncreated: 2026-09-01T09:30:00+02:00\n---\n"),
        ("unknown keys are kept in place",
         "---\ntags: [buch, 2026]\ncreated: 2026-09-01T09:30:00+02:00\nrating: 5\n---\nx\n"),
        ("comments and blank lines in frontmatter",
         "---\n# where it came from\ncreated: 2026-09-01T09:30:00+02:00\n\n# mine\nnote: \"x\"\n---\ny\n"),
        ("crlf", "---\r\ncreated: 2026-09-01T09:30:00+02:00\r\n---\r\nMarie's copy.\r\n"),
        ("no trailing newline", "---\ncreated: 2026-09-01T09:30:00+02:00\n---\nMarie's copy"),
        ("BOM", "\u{FEFF}---\ncreated: 2026-09-01T09:30:00+02:00\n---\nx\n"),
        ("umlauts and emoji", "---\n---\nFrühstück 🍞 — 日本語\n"),
        ("markdown the app knows nothing about",
         "---\n---\n# A heading\n\n- [ ] a checkbox\n\n> a quote\n\n![[cover.png]]\n"),
        ("--- inside the body", "---\n---\nabove\n\n---\n\nbelow\n"),
        ("completely empty file", ""),
        ("fractional seconds", "---\ncreated: 2026-09-01T09:30:17.632+02:00\n---\nx\n"),
    ]

    @Test(arguments: items)
    func everyShapeRoundTrips(_ testCase: (name: String, text: String)) throws {
        for id in [openID, doneID] {
            let decoded = try NoteCodec.decodeListItem(
                id: id, text: testCase.text, timeZone: vaultTimeZone)
            let encoded = NoteCodec.encode(decoded, timeZone: vaultTimeZone)
            #expect(encoded == testCase.text,
                    "\(testCase.name) at \(id.path) — \(firstDifference(testCase.text, encoded))")
        }
    }

    // MARK: - Patching

    @Test func changingTheNotesChangesOnlyTheBody() throws {
        let text = "---\ntags: [buch]\ncreated: 2026-09-01T09:30:00+02:00\n---\nold note\n"
        var item = try NoteCodec.decodeListItem(id: openID, text: text, timeZone: vaultTimeZone)
        item.notes = "new note"
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone)
            == "---\ntags: [buch]\ncreated: 2026-09-01T09:30:00+02:00\n---\nnew note\n")
    }

    @Test func clearingTheNotesEmptiesTheBodyAndKeepsTheFrontmatter() throws {
        let text = "---\ncreated: 2026-09-01T09:30:00+02:00\n---\nold note\n"
        var item = try NoteCodec.decodeListItem(id: openID, text: text, timeZone: vaultTimeZone)
        item.notes = ""
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone)
            == "---\ncreated: 2026-09-01T09:30:00+02:00\n---\n")
    }

    /// A brand-new item (empty passthrough) renders from the template: nothing but `created`.
    @Test func aFreshItemIsTheLeanestNoteInTheVault() {
        let item = ListItem(
            id: openID, list: "Read", title: "Sapiens",
            created: Fixtures.date(Fixtures.day(0), 9, 30), notes: "Marie's copy")
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone)
            == "---\ncreated: 2026-09-19T09:30:00+02:00\n---\nMarie's copy\n")
    }

    @Test func anItemWithNothingToSayWritesNoFrontmatterKey() {
        let item = ListItem(id: openID, list: "Read", title: "Sapiens")
        #expect(NoteCodec.encode(item) == "---\n---\n")
    }

    /// The file is moved *before* it is patched (filing a capture into a list, renaming an
    /// item), so the stored text belongs to the previous path. Only `created` and the body are
    /// patched, and neither depends on where the file sits.
    @Test func anItemPatchesTheFileItCameFromEvenUnderANewPath() throws {
        let capture = "---\ncreated: 2026-09-19T08:12:04+02:00\n---\nSapiens by Harari\n"
        let inboxItem = try NoteCodec.decodeInboxItem(
            id: NoteID(path: "Inbox/2026-09-19 081204.md"),
            text: capture,
            timeZone: vaultTimeZone)
        // Exactly what `fileInbox(.list)` builds: the capture's date and text carried over.
        let item = ListItem(
            id: openID, list: "Read", title: "Sapiens",
            created: inboxItem.created, notes: "", passthrough: inboxItem.passthrough)
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone)
            == "---\ncreated: 2026-09-19T08:12:04+02:00\n---\n")
    }

    // MARK: - L4: promoting an item keeps its notes

    /// The note *moves* into `Actions/` (L4), so the codec patches the list item's own file.
    /// Its body is somebody else's content — the reducer (`promoteListItem`) hands it over as
    /// the action's lead paragraph, so the action headings go **below** it, never over it.
    @Test func promotingAnItemKeepsItsNotesAboveTheActionHeadings() throws {
        let itemText = "---\ncreated: 2026-09-01T09:30:00+02:00\ntags: [buch]\n---\nMarie's copy.\n"
        let action = Action(
            id: NoteID(path: "Actions/Read Sapiens.md"),
            title: "Read Sapiens",
            status: .next,
            contexts: ["home"],
            timeEstimate: 60,
            created: Fixtures.date(Fixtures.day(-18), 9, 30),
            preamble: "Marie's copy.",
            why: "Marie keeps asking",
            what: "Read the first 50 pages",
            passthrough: NoteCodec.passthrough(itemText))

        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded.contains("Marie's copy."), "the item's notes must survive: \(encoded)")
        #expect(encoded.contains("tags: [buch]"), "unknown keys must survive: \(encoded)")
        #expect(encoded.contains("status: next"))
        #expect(encoded.contains("# Why?\nMarie keeps asking"))
        #expect(encoded.contains("# What?\nRead the first 50 pages"))
        // The notes stay first; the headings follow (R-4's shape).
        let notesAt = try #require(encoded.range(of: "Marie's copy."))
        let whyAt = try #require(encoded.range(of: "# Why?"))
        #expect(notesAt.lowerBound < whyAt.lowerBound)
        // And it is still a readable action afterwards.
        let reread = try NoteCodec.decodeAction(
            id: action.id, text: encoded, timeZone: vaultTimeZone)
        #expect(reread.why == "Marie keeps asking")
        #expect(reread.what == "Read the first 50 pages")
    }

    /// The pre-existing rule is untouched: a note that really decodes as an action and has no
    /// headings *is* its `What?`, and editing that rewrites the body rather than appending.
    @Test func aHeadinglessActionNoteStillWritesItsWhatBackAsTheBody() throws {
        let text = "---\nstatus: next\n---\nDo the thing\n"
        var action = try NoteCodec.decodeAction(
            id: NoteID(path: "Actions/A.md"), text: text, timeZone: vaultTimeZone)
        #expect(action.what == "Do the thing")
        action.what = "Do the other thing"
        #expect(NoteCodec.encode(action, timeZone: vaultTimeZone)
            == "---\nstatus: next\n---\nDo the other thing\n")
    }
}

/// R-5 — `favouriteLists:` in `GTD/Config.md`: absent means "never chosen", and the derived
/// default is never written.
struct ConfigFavouriteListsTests {

    private let id = NoteID(path: "GTD/Config.md")

    @Test func anAbsentKeyDecodesAsNoChoice() throws {
        let config = try NoteCodec.decodeConfig(id: id, text: "---\nnextCap: 15\n---\n")
        #expect(config.favouriteLists == nil)
    }

    @Test func aStoredChoiceDecodesInOrder() throws {
        let config = try NoteCodec.decodeConfig(
            id: id, text: "---\nfavouriteLists: [Read, Watch]\n---\n")
        #expect(config.favouriteLists == ["Read", "Watch"])
    }

    @Test func anEmptyStoredChoiceIsNotTheSameAsNoChoice() throws {
        let config = try NoteCodec.decodeConfig(id: id, text: "---\nfavouriteLists: []\n---\n")
        #expect(config.favouriteLists == [])
    }

    @Test(arguments: [
        "---\nnextCap: 15\n---\n# Config\n",
        "---\nfavouriteLists: [Read, Watch]\nnextCap: 15\n---\n# Config\n",
        "---\nfavouriteLists: []\n---\n",
        "---\nfavouriteLists:\n  - Read\n  - Watch\n---\n",
    ])
    func theConfigRoundTrips(text: String) throws {
        let config = try NoteCodec.decodeConfig(id: id, text: text)
        #expect(NoteCodec.encode(config) == text, "\(firstDifference(text, NoteCodec.encode(config)))")
    }

    /// The derived default must never end up in the file (R-5).
    @Test func choosingFavouritesAddsExactlyOneLineAndClearingThemTakesItAway() throws {
        let text = "---\nnextCap: 15\n---\n# Config\n"
        var config = try NoteCodec.decodeConfig(id: id, text: text)
        config.favouriteLists = ["Read", "Watch"]
        let written = NoteCodec.encode(config)
        #expect(written == "---\nnextCap: 15\nfavouriteLists: [Read, Watch]\n---\n# Config\n")

        var cleared = try NoteCodec.decodeConfig(id: id, text: written)
        cleared.favouriteLists = nil
        #expect(NoteCodec.encode(cleared) == text)
    }

    /// The lists root is overridable like every other folder (§3).
    @Test func theLayoutCarriesTheListsFolder() throws {
        let text = "---\nlayout:\n  lists: Listen\n---\n"
        let config = try NoteCodec.decodeConfig(id: id, text: text)
        #expect(config.layout.lists == "Listen")
        #expect(NoteCodec.encode(config) == text)
    }
}

/// L2 — `listIcons:` in `GTD/Config.md`: written only once an icon is picked.
struct ConfigListIconsTests {

    private let id = NoteID(path: "GTD/Config.md")

    @Test func anAbsentKeyDecodesAsNoIcons() throws {
        let config = try NoteCodec.decodeConfig(id: id, text: "---\nnextCap: 15\n---\n")
        #expect(config.listIcons.isEmpty)
    }

    @Test func pickingAnIconAddsTheMappingAndClearingItTakesItAway() throws {
        let text = "---\nnextCap: 15\n---\n# Config\n"
        var config = try NoteCodec.decodeConfig(id: id, text: text)
        config.listIcons = ["Watch": "tv", "Read": "books.vertical"]
        let written = NoteCodec.encode(config)
        #expect(written == "---\nnextCap: 15\nlistIcons:\n  Read: books.vertical\n  Watch: tv\n---\n# Config\n")
        #expect(try NoteCodec.decodeConfig(id: id, text: written).listIcons == config.listIcons)

        var cleared = try NoteCodec.decodeConfig(id: id, text: written)
        cleared.listIcons = [:]
        #expect(NoteCodec.encode(cleared) == text)
    }

    @Test func aListNameThatNeedsQuotingSurvives() throws {
        var config = try NoteCodec.decodeConfig(id: id, text: "---\nnextCap: 15\n---\n")
        config.listIcons = ["Books: to buy": "cart"]
        let back = try NoteCodec.decodeConfig(id: id, text: NoteCodec.encode(config))
        #expect(back.listIcons == ["Books: to buy": "cart"])
    }

    @Test func aHandWrittenMappingRoundTripsUntouched() throws {
        let text = "---\nlistIcons: {Read: book, Wish: cart}\nnextCap: 15\n---\n"
        let config = try NoteCodec.decodeConfig(id: id, text: text)
        #expect(config.listIcons == ["Read": "book", "Wish": "cart"])
        #expect(NoteCodec.encode(config) == text)
    }
}
