import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// N2: `encode(decode(text)) == text`, byte for byte.
///
/// These are the most valuable tests in the repo — every write the app performs goes through
/// this path, and a regression here silently rewrites the user's notes.
struct RoundTripTests {

    // MARK: - The sample vault

    @Test func everySampleVaultFileRoundTrips() throws {
        let files = SampleVault.files
        #expect(files.count >= 50)
        for path in files.keys.sorted() {
            let original = files[path]!
            let encoded = try RoundTrip.encodeDecoded(path: path, text: original)
            #expect(encoded == original, "\(path) — \(firstDifference(original, encoded))")
        }
    }

    @Test func committedSampleVaultOnDiskRoundTrips() throws {
        guard let bundleURL = SampleVault.bundleURL else { return }   // no resource bundle: skip
        let files = try SampleVault.read(tree: bundleURL)
        #expect(!files.isEmpty)
        for path in files.keys.sorted() {
            let original = files[path]!
            let encoded = try RoundTrip.encodeDecoded(path: path, text: original)
            #expect(encoded == original, "\(path) — \(firstDifference(original, encoded))")
        }
    }

    // MARK: - Hand-written nasty cases

    /// Every case below is round-tripped as an *action*, because the action codec touches the
    /// most machinery: frontmatter, two known body sections, and a checkbox list.
    static let nastyActions: [(name: String, text: String)] = [
        ("crlf everywhere",
         "---\r\nstatus: next\r\ncontexts: [mac]\r\n---\r\n# Why?\r\nBecause.\r\n\r\n# What?\r\n- [ ] Do it\r\n"),

        ("no trailing newline",
         "---\nstatus: next\n---\n# Why?\nBecause.\n\n# What?\nDo it"),

        ("empty-ish frontmatter",
         "---\nstatus: next\n---\n# Why?\n\n# What?\n"),

        ("--- inside the body",
         "---\nstatus: next\n---\n# Why?\nA thematic break follows.\n\n---\n\n# What?\nStill fine.\n"),

        ("--- as the only body line",
         "---\nstatus: next\n---\n---\n"),

        ("unknown keys in the middle, order preserved",
         "---\ntags: [a, b]\nstatus: next\npriority: high\ncontexts: [mac]\nRessources: \"\"\n---\n# Why?\nx\n"),

        ("comments and blank lines in frontmatter",
         "---\n# a comment\nstatus: next\n\n# another comment\ncontexts: [mac]\n\n---\n# Why?\nx\n"),

        ("empty keys",
         "---\nstatus: next\nscheduled:\nRessources: \"\"\ncontexts: []\n---\n# What?\nx\n"),

        ("block sequence contexts",
         "---\nstatus: next\ncontexts:\n  - mac\n  - deep-work\n---\n# Why?\nx\n"),

        ("single quoted and folded scalars",
         "---\nstatus: next\nnote: 'it''s fine'\nfolded: >\n  a folded\n  scalar\nliteral: |\n  line one\n  line two\n---\n# Why?\nx\n"),

        ("umlauts, emoji and CJK",
         "---\nstatus: next\nwaitingFor: \"Jürgen Müller\"\n---\n# Why?\nFrühstück 🍞 café — 日本語テキスト\n\n# What?\n- [ ] Sonnencreme auftragen\n"),

        ("tabs in the checkbox list",
         "---\nstatus: next\n---\n# What?\n- [ ] Top\n\t- [ ] Nested with a tab\n\t\t- [x] Deeper\n"),

        ("unknown body sections preserved",
         "---\nstatus: next\n---\n# Why?\nx\n\n# Notes from Obsidian\nSomething the app knows nothing about.\n\n# What?\ny\n\n# Attachments\n![[a.png]]\n"),

        ("text before the first heading",
         "---\nstatus: next\n---\nA stray paragraph the user typed at the top.\n\n# Why?\nx\n"),

        ("closing delimiter is ...",
         "---\nstatus: next\n...\n# Why?\nx\n"),

        ("trailing whitespace on lines",
         "---\nstatus: next   \ncontexts: [mac]\t\n---\n# Why?   \nx  \n"),

        ("BOM at the start",
         "\u{FEFF}---\nstatus: next\n---\n# Why?\nx\n"),

        ("blank lines everywhere in the body",
         "---\nstatus: next\n---\n\n\n# Why?\n\n\nx\n\n\n\n# What?\n\n\n"),

        ("fenced code block containing a heading",
         "---\nstatus: next\n---\n# What?\n```\n# not a heading\nstatus: fake\n```\n"),

        ("duplicate known heading",
         "---\nstatus: next\n---\n# Why?\nfirst\n\n# Why?\nsecond\n"),

        ("deep-linked project with alias",
         "---\nstatus: next\nproject: \"[[Projects/Applications/DAAD/DAAD|DAAD]]\"\n---\n# Why?\nx\n"),

        ("bare project title",
         "---\nstatus: next\nproject: \"[[DAAD]]\"\n---\n# Why?\nx\n"),

        ("legacy timeEstimate zero stays untouched",
         "---\nstatus: next\ntimeEstimate: 0\n---\n# Why?\nx\n"),

        ("quoted key",
         "---\n\"status\": next\ncontexts: [mac]\n---\n# Why?\nx\n"),

        ("fractional-second timestamps",
         "---\nstatus: next\ncreated: 2026-09-13T23:20:17.632+02:00\ncompletedDate: 2026-09-14T08:00:00Z\n---\n# Why?\nx\n"),

        ("no body at all",
         "---\nstatus: next\n---\n"),

        ("frontmatter only, no closing newline",
         "---\nstatus: next\n---"),
    ]

    /// Files that carry no required key at all, so they can be pushed through the *total*
    /// codecs (routine, area) and through `FrontmatterDocument` itself.
    static let nastyDocuments: [(name: String, text: String)] = nastyActions + [
        ("no frontmatter at all", "# Why?\nBecause.\n\n# What?\nDo it\n"),
        ("empty frontmatter", "---\n---\n# Why?\n\n# What?\n"),
        ("empty frontmatter, nothing else", "---\n---\n"),
        ("windows line endings without frontmatter", "Just a body.\r\nWith two lines.\r\n"),
        ("completely empty file", ""),
        ("a single newline", "\n"),
        ("only a --- line", "---\n"),
        ("only whitespace", "   \n\t\n"),
        ("frontmatter delimiter mid-file is not frontmatter", "text\n---\nkey: value\n---\nmore\n"),
        ("mixed line endings", "---\r\nstatus: next\n---\r\n# Why?\nx\r\n"),
        ("tabs in frontmatter values", "---\nnote: \"a\tb\"\n---\nbody\n"),
    ]

    /// Whatever the file is, splitting and re-joining it must be the identity, and a
    /// `FrontmatterDocument` that nobody edits must print its input back unchanged.
    @Test(arguments: nastyDocuments)
    func documentIsLosslessWithoutEditing(_ testCase: (name: String, text: String)) throws {
        #expect(RawText.join(RawText.split(testCase.text)) == testCase.text, "\(testCase.name)")
        let doc = try FrontmatterDocument(text: testCase.text, path: "X.md")
        #expect(doc.text == testCase.text,
                "\(testCase.name) — \(firstDifference(testCase.text, doc.text))")
    }

    /// The routine codec requires no frontmatter key, so it can round-trip every shape above.
    @Test(arguments: nastyDocuments)
    func nastyDocumentRoundTripsAsARoutine(_ testCase: (name: String, text: String)) throws {
        let id = NoteID(path: "GTD/Routines/Nasty.md")
        let routine = try NoteCodec.decodeRoutine(id: id, text: testCase.text)
        let encoded = NoteCodec.encode(routine)
        #expect(encoded == testCase.text,
                "\(testCase.name) — \(firstDifference(testCase.text, encoded))")
    }

    @Test(arguments: nastyActions)
    func nastyActionRoundTrips(_ testCase: (name: String, text: String)) throws {
        let id = NoteID(path: "Actions/Nasty.md")
        let decoded = try NoteCodec.decodeAction(id: id, text: testCase.text, timeZone: vaultTimeZone)
        let encoded = NoteCodec.encode(decoded, timeZone: vaultTimeZone)
        #expect(encoded == testCase.text,
                "\(testCase.name) — \(firstDifference(testCase.text, encoded))")
    }

    @Test(arguments: nastyActions)
    func nastyActionSurvivesTwoRoundTrips(_ testCase: (name: String, text: String)) throws {
        let id = NoteID(path: "Actions/Nasty.md")
        var text = testCase.text
        for _ in 0..<3 {
            let decoded = try NoteCodec.decodeAction(id: id, text: text, timeZone: vaultTimeZone)
            text = NoteCodec.encode(decoded, timeZone: vaultTimeZone)
        }
        #expect(text == testCase.text, "\(testCase.name) — \(firstDifference(testCase.text, text))")
    }

    // MARK: - Other note kinds, nasty

    @Test func inboxItemWithoutTrailingNewlineRoundTrips() throws {
        let text = "---\ncreated: 2026-09-08T07:12:33+02:00\n---\nbuy new running shoes"
        let id = NoteID(path: "Inbox/2026-09-08 071233.md")
        let item = try NoteCodec.decodeInboxItem(id: id, text: text, timeZone: vaultTimeZone)
        #expect(item.text == "buy new running shoes")
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone) == text)
    }

    @Test func multiLineInboxCaptureRoundTrips() throws {
        let text = "---\ncreated: 2026-09-08T07:12:33+02:00\n---\nline one\n\nline three — with an em dash\n"
        let id = NoteID(path: "Inbox/x.md")
        let item = try NoteCodec.decodeInboxItem(id: id, text: text, timeZone: vaultTimeZone)
        #expect(item.text == "line one\n\nline three — with an em dash")
        #expect(NoteCodec.encode(item, timeZone: vaultTimeZone) == text)
    }

    @Test func projectWithUnknownSectionsAndNestedStepsRoundTrips() throws {
        let text = """
        ---
        kind: project
        status: on-hold
        area: "[[Projects/Applications/Applications]]"
        obsidianPlugin: {foo: 1}
        ---
        # Outcome
        Something.

        # Resources
        - [[Some note]]

        # Steps
        - [x] Done step → [[Actions/Done step]]
        - [ ] Open step
            - [ ] A sub-item the app flattens
        * [ ] Star bullet

        # Log
        - 2026-09-08 First
        - 2026-09-09 Second — with a dash

        # Notes

        """
        let id = NoteID(path: "Projects/X/X.md")
        let project = try NoteCodec.decodeProject(id: id, text: text)
        #expect(project.status == .onHold)
        #expect(project.steps.count == 4)
        #expect(project.steps[0].promotedTo == NoteID(path: "Actions/Done step.md"))
        #expect(project.log.count == 2)
        #expect(NoteCodec.encode(project) == text)
    }

    @Test func routineWithProseAroundTheListRoundTrips() throws {
        let text = """
        ---
        time: "07:00"
        tags: [routine]
        ---
        Some intro text.

        - [ ] Wake up
        \t- [ ] Drink water
        - [ ] Frühstück
            - [ ] Brainsmoothie

        A closing remark.

        """
        let id = NoteID(path: "GTD/Routines/Morning.md")
        let routine = try NoteCodec.decodeRoutine(id: id, text: text)
        #expect(routine.time == DayTime(hour: 7, minute: 0))
        #expect(routine.steps.count == 2)
        #expect(routine.steps[0].substeps == ["Drink water"])
        #expect(routine.steps[1].substeps == ["Brainsmoothie"])
        #expect(NoteCodec.encode(routine) == text)
    }

    @Test func weeklyReviewRoundTrips() throws {
        let files = SampleVault.files
        let path = "GTD/Reviews/2026/KW 37.md"
        let text = try #require(files[path])
        let review = try NoteCodec.decodeWeeklyReview(
            id: NoteID(path: path), text: text, timeZone: vaultTimeZone)
        #expect(review.year == 2026)
        #expect(review.week == 37)
        #expect(review.systemFixNotes.count == 1)
        #expect(NoteCodec.encode(review, timeZone: vaultTimeZone) == text)
    }

    @Test func configWithExtraKeysRoundTrips() throws {
        let text = """
        ---
        contexts: [mac, phone]
        onTheGoContexts: [phone]
        nextCap: 12
        somethingElse: kept
        ---
        # Config
        Hand-edited.

        """
        let config = try NoteCodec.decodeConfig(id: NoteID(path: "GTD/Config.md"), text: text)
        #expect(config.nextCap == 12)
        #expect(config.contexts == ["mac", "phone"])
        #expect(NoteCodec.encode(config) == text)
    }
}
