import Testing
@testable import DesignSystem

/// STYLEGUIDE §4.4 — Obsidian-style live preview of note bodies.
struct MarkdownRenderingTests {

    private func shown(_ text: String) -> String { MarkdownRendering.display(text).text }

    /// The attributes of the first run covering `needle` in the display text.
    private func attributes(of needle: String, in text: String) -> MarkdownAttributes? {
        let (display, runs) = MarkdownRendering.display(text)
        guard let range = display.range(of: needle) else { return nil }
        let offset = display.utf16.distance(from: display.utf16.startIndex, to: range.lowerBound)
        return runs.first { $0.range.contains(offset) }?.attributes ?? MarkdownAttributes()
    }

    // MARK: - Inline

    @Test func emphasisLosesItsMarkup() {
        #expect(shown("**bold**, *it*, _it_, ~~gone~~, ==mark==") == "bold, it, it, gone, mark")
        #expect(attributes(of: "bold", in: "**bold**")?.bold == true)
        #expect(attributes(of: "gone", in: "~~gone~~")?.strike == true)
        #expect(attributes(of: "mark", in: "==mark==")?.highlight == true)
    }

    @Test func nestedEmphasisCombines() {
        let inner = attributes(of: "both", in: "*a **both** c*")
        #expect(inner?.bold == true && inner?.italic == true)
        #expect(shown("*a **both** c*") == "a both c")
    }

    @Test func underscoresInsideWordsAreText() {
        #expect(shown("snake_case_name") == "snake_case_name")
        #expect(shown("2 * 3 * 4") == "2 * 3 * 4")
    }

    @Test func codeIsLiteral() {
        #expect(shown("run `a*b*c` now") == "run a*b*c now")
        let code = attributes(of: "a*b*c", in: "`a*b*c`")
        #expect(code?.code == true && code?.italic == false)
    }

    @Test func linksShowTheirText() {
        #expect(shown("see [docs](https://x.org/a)") == "see docs")
        #expect(attributes(of: "docs", in: "[docs](https://x.org)")?.link == true)
        #expect(shown("[[Project Alpha]] and [[Note|this one]]") == "Project Alpha and this one")
        #expect(attributes(of: "https", in: "go to https://x.org now")?.link == true)
    }

    @Test func escapedMarkupStaysLiteral() {
        #expect(shown(#"\*not italic\*"#) == "*not italic*")
    }

    // MARK: - Blocks

    @Test func headingsLoseTheirHashes() {
        #expect(shown("## Plan") == "Plan")
        #expect(attributes(of: "Plan", in: "## Plan")?.heading == 2)
        #expect(shown("#tag") == "#tag")
    }

    @Test func listsShowDotsAndBoxes() {
        #expect(shown("- a\n* b\n- [ ] c\n- [x] d") == "• a\n• b\n☐ c\n☑ d")
        let done = attributes(of: "d", in: "- [x] d")
        #expect(done?.strike == true && done?.muted == true)
    }

    @Test func quotesAreMuted() {
        #expect(shown("> said") == "said")
        #expect(attributes(of: "said", in: "> said")?.muted == true)
    }

    @Test func fencedCodeIsNotParsed() {
        let text = "```\n**x**\n```\n**y**"
        #expect(shown(text) == "```\n**x**\n```\ny")
        #expect(attributes(of: "**x**", in: text)?.codeBlock == true)
    }

    // MARK: - Caret line

    @Test func theCaretLineShowsItsMarkupMuted() {
        let text = "**a**\n**b**"
        let runs = MarkdownRendering.runs(text, selection: 7..<7)
        // Line 1 (not active): the stars are hidden; line 2 (active): shown, muted.
        #expect(runs.contains { $0.range == 0..<2 && $0.attributes.hidden })
        #expect(runs.contains { $0.range == 6..<8 && $0.attributes.muted && !$0.attributes.hidden })
    }

    @Test func withoutFocusEveryLineIsRendered() {
        let runs = MarkdownRendering.runs("# A", selection: nil)
        #expect(runs.contains { $0.range == 0..<2 && $0.attributes.hidden })
    }

    @Test func boxesStayDrawnOnTheCaretLine() {
        let runs = MarkdownRendering.runs("- [ ] a", selection: 7..<7)
        #expect(runs.contains { $0.range == 2..<5 && $0.attributes.checkbox == false })
        #expect(runs.contains { $0.range == 0..<2 && $0.attributes.hidden })
    }

    /// Return at the end of a task leaves the caret at the start of the new item; the item it
    /// left keeps its box (the box was lost on screen, 2026-09-24).
    @Test func theItemAboveANewTaskKeepsItsBox() {
        let text = "- [ ] a\n- [ ] b\n- [ ] "
        let end = text.utf16.count
        for selection in [end..<end, 15..<15, 14..<14] {
            let runs = MarkdownRendering.runs(text, selection: selection)
            for box in [2..<5, 10..<13, 18..<21] {
                #expect(runs.contains { $0.range == box && $0.attributes.checkbox == false
                    && !$0.attributes.hidden })
            }
        }
    }

    @Test func aClickFindsTheBox() {
        let text = "intro\n- [ ] call"
        #expect(MarkdownRendering.checkbox(at: 9, in: text) == 8..<11)
        #expect(MarkdownRendering.checkbox(at: 13, in: text) == nil)
    }
}
