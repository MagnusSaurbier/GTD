import Testing
import Foundation
import GTDModel
@testable import GTDMarkdown

/// The line-level machinery the codec is built on.
struct PrimitiveTests {

    // MARK: - RawText

    @Test(arguments: [
        "", "\n", "a", "a\n", "a\nb", "a\r\nb\r\n", "\r\n", "a\n\n\nb",
        "a\rb\n", "line with \u{2028} separator\n", "\u{FEFF}bom\n",
    ])
    func splitAndJoinAreTheIdentity(_ text: String) {
        #expect(RawText.join(RawText.split(text)) == text)
    }

    @Test func keepsEachLinesOwnTerminator() {
        let lines = RawText.split("a\r\nb\nc")
        #expect(lines.map(\.content) == ["a", "b", "c"])
        #expect(lines.map(\.terminator) == ["\r\n", "\n", ""])
    }

    @Test func crlfIsNotTreatedAsOneCharacter() {
        // Swift's `Character` view merges "\r\n"; the splitter must not.
        #expect("a\r\nb".count == 3)
        #expect(RawText.split("a\r\nb").count == 2)
    }

    @Test func indentWidthCountsTabsAsFourColumns() {
        #expect(RawLine(content: "\tx").indentWidth == 4)
        #expect(RawLine(content: "  \tx").indentWidth == 4)
        #expect(RawLine(content: "     x").indentWidth == 5)
        #expect(RawLine(content: "x").indentWidth == 0)
    }

    @Test func blockDropsExactlyOneTrailingNewline() {
        #expect(RawText.block("a\nb\n", terminator: "\n").map(\.content) == ["a", "b"])
        #expect(RawText.block("a\nb", terminator: "\n").map(\.content) == ["a", "b"])
        #expect(RawText.block("a\n\n", terminator: "\n").map(\.content) == ["a", ""])
        #expect(RawText.block("", terminator: "\n").isEmpty)
    }

    // MARK: - FrontmatterDocument

    @Test func recognisesTopLevelKeyLines() {
        #expect(FrontmatterDocument.parseKeyLine("status: next")?.key == "status")
        #expect(FrontmatterDocument.parseKeyLine("status:")?.key == "status")
        #expect(FrontmatterDocument.parseKeyLine("\"quoted key\": v")?.key == "quoted key")
        #expect(FrontmatterDocument.parseKeyLine("'single': v")?.key == "single")
        #expect(FrontmatterDocument.parseKeyLine("url: http://x")?.key == "url")
        #expect(FrontmatterDocument.parseKeyLine("time: \"07:00\"")?.key == "time")
        // Not top-level keys:
        #expect(FrontmatterDocument.parseKeyLine("  nested: v") == nil)
        #expect(FrontmatterDocument.parseKeyLine("- item: v") == nil)
        #expect(FrontmatterDocument.parseKeyLine("---") == nil)
        #expect(FrontmatterDocument.parseKeyLine("# comment: not a key") == nil)
        #expect(FrontmatterDocument.parseKeyLine("plain scalar") == nil)
        #expect(FrontmatterDocument.parseKeyLine("a:b") == nil)      // no space after the colon
    }

    @Test func onlyTheFirstLineCanOpenFrontmatter() throws {
        let text = "Some text\n---\nnot: frontmatter\n---\n"
        let doc = try FrontmatterDocument(text: text, path: "x.md")
        #expect(!doc.hasFrontmatter)
        #expect(doc.scalar("not") == nil)
        #expect(doc.text == text)
    }

    @Test func unterminatedFrontmatterIsAllBody() throws {
        let doc = try FrontmatterDocument(text: "---\nstatus: next\n", path: "x.md")
        #expect(!doc.hasFrontmatter)
        #expect(doc.text == "---\nstatus: next\n")
    }

    @Test func settingAKeyThatHasABlockValueReplacesTheWholeBlock() throws {
        var doc = try FrontmatterDocument(text: """
        ---
        before: 1
        contexts:
          - mac
          - deep-work
        after: 2
        ---
        body

        """, path: "x.md")
        doc.setValue("contexts", "[phone]")
        #expect(doc.text == "---\nbefore: 1\ncontexts: [phone]\nafter: 2\n---\nbody\n")
    }

    @Test func settingAnIdenticalLineChangesNoBytes() throws {
        var doc = try FrontmatterDocument(text: "---\nstatus: next\n---\n", path: "x.md")
        doc.setValue("status", "next")
        #expect(doc.text == "---\nstatus: next\n---\n")
        // A line that differs only in spacing *is* rewritten — but only because it differs, and
        // only that line. The codec avoids this by comparing decoded values, not rendered text.
        var spaced = try FrontmatterDocument(text: "---\nstatus:   next\nkeep: me\n---\n", path: "x.md")
        spaced.setValue("status", "next")
        #expect(spaced.text == "---\nstatus: next\nkeep: me\n---\n")
    }

    /// A multi-line quoted scalar can hide something that looks like a top-level key. Reading is
    /// still correct (Yams does that), and nothing is corrupted as long as the codec does not
    /// patch such a key — which it never does, because it only patches the schema's own keys.
    @Test func aMultiLineScalarWithAKeyInsideStillRoundTrips() throws {
        let text = "---\nstatus: next\nnote: \"line one\nlooks: like a key\"\n---\nbody\n"
        let doc = try FrontmatterDocument(text: text, path: "x.md")
        #expect(doc.scalar("note") == "line one looks: like a key")
        #expect(doc.text == text)
        var patched = doc
        patched.setValue("status", "done")
        #expect(patched.text == "---\nstatus: done\nnote: \"line one\nlooks: like a key\"\n---\nbody\n")
    }

    /// Yams refuses duplicate mapping keys, and so does the codec: guessing which of two
    /// `status:` lines the user meant would be exactly the silent coercion N2 forbids.
    @Test func duplicateKeysBecomeAVaultIssue() {
        #expect {
            _ = try FrontmatterDocument(text: "---\nstatus: next\nstatus: done\n---\n", path: "x.md")
        } throws: { error in
            guard case let NoteCodecError.unreadable(path, reason) = error else { return false }
            return path == "x.md" && reason.lowercased().contains("duplicat")
        }
    }

    @Test func aKeysRegionStopsBeforeBlankLinesAndComments() throws {
        var doc = try FrontmatterDocument(text: """
        ---
        a: 1

        # a comment about b
        b: 2
        ---

        """, path: "x.md")
        doc.setValue("a", "9")
        #expect(doc.text == "---\na: 9\n\n# a comment about b\nb: 2\n---\n")
        doc.removeValue("b")
        #expect(doc.text == "---\na: 9\n\n# a comment about b\n---\n")
    }

    @Test func aQuotedKeyKeepsItsQuotesWhenPatched() throws {
        var doc = try FrontmatterDocument(text: "---\n\"status\": next\n---\n", path: "x.md")
        doc.setValue("status", "done")
        #expect(doc.text == "---\n\"status\": done\n---\n")
    }

    @Test func frontmatterIsCreatedWhenThereIsNone() throws {
        var doc = try FrontmatterDocument(text: "just a body\n", path: "x.md")
        doc.setValue("status", "next", canonicalOrder: NoteCodec.Keys.action)
        #expect(doc.text == "---\nstatus: next\n---\njust a body\n")
    }

    @Test func newKeysGoIntoSchemaOrderWithoutMovingExistingOnes() throws {
        var doc = try FrontmatterDocument(
            text: "---\nzzz: keep me first\nstatus: next\ncreated: x\n---\n", path: "x.md")
        doc.setValue("due", "2026-01-01", canonicalOrder: NoteCodec.Keys.action)
        #expect(doc.text == "---\nzzz: keep me first\nstatus: next\ndue: 2026-01-01\ncreated: x\n---\n")
    }

    // MARK: - BodySections

    @Test func splitsOnLevelOneHeadingsOnly() {
        let sections = BodySections(lines: RawText.split("""
        intro
        # One
        a
        ## Sub
        b
        # Two
        c

        """))
        #expect(sections.prefix.map(\.content) == ["intro"])
        #expect(sections.sections.map(\.title) == ["One", "Two"])
        #expect(sections.sections[0].text == "a\n## Sub\nb")
        #expect(sections.sections[1].text == "c")
    }

    @Test func headingsInFencedCodeAreNotHeadings() {
        let sections = BodySections(lines: RawText.split("""
        # Real
        ```md
        # Fake
        ```
        ~~~
        # Also fake
        ~~~

        """))
        #expect(sections.sections.map(\.title) == ["Real"])
    }

    @Test func normalisesHeadingsForMatching() {
        #expect(BodySections.normalize("Why?") == BodySections.normalize("why"))
        #expect(BodySections.normalize("What ?") == BodySections.normalize("WHAT"))
        #expect(BodySections.normalize("System fixes") == "systemfixes")
        #expect(BodySections.normalize("Outcome") != BodySections.normalize("Steps"))
    }

    @Test func closedAtxHeadingsAreUnderstood() {
        #expect(BodySections.headingTitle("# Why? #") == "Why?")
        #expect(BodySections.headingTitle("## Not level one") == nil)
        #expect(BodySections.headingTitle("#NoSpace") == nil)
    }

    @Test func settingASectionKeepsTheBlankLineBeforeTheNextHeading() {
        var sections = BodySections(lines: RawText.split("# A\nold\n\n# B\nkeep\n"))
        sections.setText("A", "new")
        #expect(sections.text == "# A\nnew\n\n# B\nkeep\n")
    }

    @Test func insertingASectionAddsOneSeparatorBlankLine() {
        var sections = BodySections(lines: RawText.split("# Why?\nbecause\n"))
        sections.setText("What?", "do it", canonicalOrder: NoteCodec.Headings.action)
        #expect(sections.text == "# Why?\nbecause\n\n# What?\ndo it\n")

        var reversed = BodySections(lines: RawText.split("# What?\ndo it\n"))
        reversed.setText("Why?", "because", canonicalOrder: NoteCodec.Headings.action)
        #expect(reversed.text == "# Why?\nbecause\n\n# What?\ndo it\n")
    }

    // MARK: - YAML scalars

    @Test func quotesOnlyWhatHasToBeQuoted() {
        #expect(YAMLScalar.string("next") == "next")
        #expect(YAMLScalar.string("deep-work") == "deep-work")
        #expect(YAMLScalar.string("") == "\"\"")
        #expect(YAMLScalar.string("true") == "\"true\"")
        #expect(YAMLScalar.string("no") == "\"no\"")
        #expect(YAMLScalar.string("42") == "\"42\"")
        #expect(YAMLScalar.string("07:00") == "\"07:00\"")
        #expect(YAMLScalar.string("2026-09-19") == "\"2026-09-19\"")
        #expect(YAMLScalar.string("- dash") == "\"- dash\"")
        #expect(YAMLScalar.string("a: b") == "\"a: b\"")
        #expect(YAMLScalar.string(" padded ") == "\" padded \"")
        #expect(YAMLScalar.flowList(["mac", "deep-work"]) == "[mac, deep-work]")
        #expect(YAMLScalar.flowList([]) == "[]")
    }

    @Test func escapesInDoubleQuotedScalars() {
        #expect(YAMLScalar.quoted("a\"b\\c") == "\"a\\\"b\\\\c\"")
        #expect(YAMLScalar.quoted("a\nb") == "\"a\\nb\"")
    }

    /// `GTDModel.Checkbox.scan` (used by `Action.checkboxes` and by the reducer's
    /// `toggleCheckbox`) and this target's full parser must agree on what a checkbox is —
    /// otherwise the reducer toggles a different line than the UI shows.
    @Test func theModelsCheckboxScanAgreesWithTheCodec() {
        let markdown = """
        - [ ] one
        * [x] two
        \t- [ ] nested
        - not a checkbox
        -[ ] no space
        - [-] custom state
        + [X] plus bullets are not task lists here
        text
        """
        let model = Checkbox.scan(markdown)
        let codec = CheckboxList.parse(RawText.split(markdown)).map(\.checkbox)
        #expect(model == codec)
        #expect(model.count == 3)
    }

    @Test func roundTripsEveryAwkwardScalarThroughYams() throws {
        for value in FidelityTests.awkwardStrings {
            let text = "---\nk: \(YAMLScalar.string(value))\n---\n"
            let doc = try FrontmatterDocument(text: text, path: "x.md")
            #expect(doc.scalar("k") == (value.isEmpty ? nil : value), "\(value)")
        }
    }
}
