import Testing
@testable import GTDModel

/// `Action.body` is the whole note body; `why`, `what` and `preamble` are views over it
/// (2026-09-24). These pin the grammar the views rely on.
struct NoteBodyTests {

    private let messy = """
    Lead paragraph.

    # Why?
    The reason.

    # Notes
    Keep this.
    ```
    # not a heading
    ```

    # What?
    - [ ] One
    - [x] Two

    # Attachments
    ![[scan.pdf]]
    """

    // MARK: - Reading

    @Test func sectionsAreReadByTitleAndFencesAreNotHeadings() {
        #expect(NoteBody.text(of: "Why?", in: messy) == "The reason.")
        #expect(NoteBody.text(of: "what", in: messy) == "- [ ] One\n- [x] Two")
        #expect(NoteBody.text(of: "Notes", in: messy) == "Keep this.\n```\n# not a heading\n```")
        #expect(NoteBody.text(of: "Steps", in: messy) == nil)
        #expect(NoteBody.prefix(of: messy) == "Lead paragraph.")
        #expect(NoteBody.hasAnySection(of: NoteBody.actionSections, in: messy))
    }

    @Test func actionViewsReadTheirPartOfTheBody() {
        let action = Action(id: NoteID(path: "Actions/A.md"), title: "A", status: .next, body: messy)
        #expect(action.preamble == "Lead paragraph.")
        #expect(action.why == "The reason.")
        #expect(action.what == "- [ ] One\n- [x] Two")
        #expect(action.checkboxes.count == 2)
    }

    /// A body without either heading is one long `What?`, never a lead paragraph as well.
    @Test func aHeadinglessBodyIsTheWhat() {
        let action = Action(id: NoteID(path: "Actions/A.md"), title: "A", status: .someday,
                            body: "Just a line.\n")
        #expect(action.what == "Just a line.")
        #expect(action.why == "")
        #expect(action.preamble == "")
    }

    // MARK: - Writing

    @Test func settingASectionChangesOnlyItsLines() {
        var action = Action(id: NoteID(path: "Actions/A.md"), title: "A", status: .next, body: messy)
        action.why = "A different reason."
        #expect(action.body == messy.replacingOccurrences(of: "The reason.", with: "A different reason."))
        action.what = "- [x] One\n- [x] Two"
        #expect(action.body == messy
            .replacingOccurrences(of: "The reason.", with: "A different reason.")
            .replacingOccurrences(of: "- [ ] One", with: "- [x] One"))
        action.preamble = "Corrected lead."
        #expect(action.body.hasPrefix("Corrected lead.\n\n# Why?"))
    }

    @Test func aMissingSectionIsInsertedInCanonicalOrder() {
        #expect(NoteBody.setText("What?", "- [ ] Step", in: "# Why?\nBecause.", canonicalOrder: NoteBody.actionSections)
            == "# Why?\nBecause.\n\n# What?\n- [ ] Step")
        #expect(NoteBody.setText("Why?", "Because.", in: "# What?\nDo it.", canonicalOrder: NoteBody.actionSections)
            == "# Why?\nBecause.\n\n# What?\nDo it.")
        // Nothing is added for an empty text.
        #expect(NoteBody.setText("What?", "", in: "# Why?\nBecause.", canonicalOrder: NoteBody.actionSections)
            == "# Why?\nBecause.")
    }

    @Test func settingTheWhatOfAHeadinglessBodyReplacesIt() {
        var action = Action(id: NoteID(path: "Actions/A.md"), title: "A", status: .someday, body: "Do the thing")
        action.what = "Do the other thing"
        #expect(action.body == "Do the other thing")
    }

    // MARK: - Composing

    @Test func theEmptyActionBodyIsTheTemplate() {
        #expect(Action(id: NoteID(path: "Actions/A.md"), title: "A", status: .next).body == "# Why?\n\n# What?")
        #expect(NoteBody.compose(sections: [("Why?", "a"), ("What?", "b")]) == "# Why?\na\n\n# What?\nb")
        #expect(NoteBody.compose(prefix: "Lead.\n", sections: [("Why?", ""), ("What?", "b")])
            == "Lead.\n\n# Why?\n\n# What?\nb")
    }

    // MARK: - Ensuring the action headings

    @Test func ensuringAddsOnlyWhatIsMissing() {
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: messy) == messy)
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: "# Why?\nBecause.")
            == "# Why?\nBecause.\n\n# What?")
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: "# What?\nDo it.")
            == "# Why?\n\n# What?\nDo it.")
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: "")
            == "# Why?\n\n# What?")
        // Other headings only: the two are appended, in order.
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: "# Notes\nKeep.")
            == "# Notes\nKeep.\n\n# Why?\n\n# What?")
    }

    /// A headingless body is the `What?`, so that is where its text goes.
    @Test func ensuringPutsAHeadinglessBodyUnderWhat() {
        #expect(NoteBody.ensuringSections(NoteBody.actionSections, in: "Just a line.\n\n")
            == "# Why?\n\n# What?\nJust a line.")
    }
}
