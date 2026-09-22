import Testing
@testable import DesignSystem

/// STYLEGUIDE §4.5 — the Obsidian list shortcuts of the note-body fields. `|` marks the caret,
/// `[`…`]` is not used as a selection marker because checkboxes need the brackets; a selection is
/// written `«…»`.
struct ListEditingTests {

    /// Applies `command` to `marked` (caret `|` or selection `«…»`) and returns the result in the
    /// same notation, or `nil` when nothing changed.
    private func run(_ command: ListEditCommand, _ marked: String) -> String? {
        let (text, selection) = unmark(marked)
        guard let edit = ListEditing.edit(command, text: text, selection: selection) else { return nil }
        var units = Array(text.utf16)
        units.replaceSubrange(edit.range, with: Array(edit.replacement.utf16))
        let result = String(decoding: units, as: UTF16.self)
        return mark(result, edit.selection)
    }

    private func unmark(_ marked: String) -> (String, Range<Int>) {
        var text = "", lower = 0, upper = 0
        for character in marked {
            switch character {
            case "|": lower = text.utf16.count; upper = lower
            case "«": lower = text.utf16.count
            case "»": upper = text.utf16.count
            default: text.append(character)
            }
        }
        return (text, lower..<upper)
    }

    private func mark(_ text: String, _ selection: Range<Int>) -> String {
        var units = Array(text.utf16)
        if selection.isEmpty {
            units.insert(contentsOf: "|".utf16, at: selection.lowerBound)
        } else {
            units.insert(contentsOf: "»".utf16, at: selection.upperBound)
            units.insert(contentsOf: "«".utf16, at: selection.lowerBound)
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - Toggle bullet list (⇧⌘L)

    @Test func bulletListAddsAndRemovesTheMarker() {
        #expect(run(.toggleBulletList, "buy mi|lk") == "- buy mi|lk")
        #expect(run(.toggleBulletList, "- buy mi|lk") == "buy mi|lk")
    }

    @Test func bulletListKeepsIndentationAndTurnsNumbersIntoBullets() {
        #expect(run(.toggleBulletList, "  3. st|ep") == "  - st|ep")
    }

    @Test func bulletListOnACheckboxRemovesTheWholeListMarker() {
        #expect(run(.toggleBulletList, "- [x] do|ne") == "do|ne")
    }

    @Test func bulletListOverMixedLinesBulletsTheRestFirst() {
        #expect(run(.toggleBulletList, "«a\n- b\nc»") == "«- a\n- b\n- c»")
        #expect(run(.toggleBulletList, "«- a\n- [ ] b»") == "«a\nb»")
    }

    @Test func blankLinesInsideASelectionStayBlank() {
        #expect(run(.toggleBulletList, "«a\n\nb»") == "«- a\n\n- b»")
    }

    @Test func anEmptyFieldGetsAMarker() {
        #expect(run(.toggleBulletList, "|") == "- |")
    }

    @Test func aSelectionEndingAtALineStartLeavesThatLineOut() {
        #expect(run(.toggleBulletList, "«a\n»b") == "«- a\n»b")
    }

    @Test func onlyTheCaretsLineChanges() {
        #expect(run(.toggleBulletList, "first\nsec|ond\nthird") == "first\n- sec|ond\nthird")
    }

    // MARK: - Cycle bullet / checkbox (⌥⌘L)

    @Test func cycleGoesPlainBulletCheckboxPlain() {
        #expect(run(.cycleListChecklist, "ta|sk") == "- ta|sk")
        #expect(run(.cycleListChecklist, "- ta|sk") == "- [ ] ta|sk")
        #expect(run(.cycleListChecklist, "- [ ] ta|sk") == "ta|sk")
        #expect(run(.cycleListChecklist, "- [x] ta|sk") == "ta|sk")
    }

    @Test func cycleFollowsTheFirstLine() {
        #expect(run(.cycleListChecklist, "«- a\nb\n- [ ] c»") == "«- [ ] a\n- [ ] b\n- [ ] c»")
    }

    // MARK: - Toggle checkbox (⌥L)

    @Test func checkboxTogglesBetweenOpenAndDone() {
        #expect(run(.toggleCheckbox, "- [ ] ca|ll") == "- [x] ca|ll")
        #expect(run(.toggleCheckbox, "- [x] ca|ll") == "- [ ] ca|ll")
        #expect(run(.toggleCheckbox, "- [/] ca|ll") == "- [ ] ca|ll")
    }

    @Test func checkboxTurnsAnyLineIntoAnOpenCheckbox() {
        #expect(run(.toggleCheckbox, "ca|ll") == "- [ ] ca|ll")
        #expect(run(.toggleCheckbox, "* ca|ll") == "* [ ] ca|ll")
        #expect(run(.toggleCheckbox, "1. ca|ll") == "- [ ] ca|ll")
    }

    @Test func checkboxTogglesEachSelectedLineOnItsOwn() {
        #expect(run(.toggleCheckbox, "«- [ ] a\n- [x] b»") == "«- [x] a\n- [ ] b»")
    }

    // MARK: - Caret and text

    @Test func aCaretInsideTheMarkerLandsAfterTheNewOne() {
        #expect(run(.cycleListChecklist, "-| x") == "- [ ] |x")
        #expect(run(.toggleBulletList, "  |x") == "  - |x")
    }

    @Test func textOnOtherLinesAndNonASCIIContentSurvive() {
        #expect(run(.toggleCheckbox, "Überblick 🎯\nzwei|") == "Überblick 🎯\n- [ ] zwei|")
    }

    @Test func windowsLineEndsStillSplitLines() {
        #expect(run(.toggleBulletList, "a\r\nb|") == "a\r\n- b|")
    }

    @Test func aSeparatorLineIsNotABullet() {
        #expect(run(.toggleBulletList, "--|-") == "- --|-")
    }

    // MARK: - Return in a list

    private func newline(_ marked: String) -> String? {
        let (text, selection) = unmark(marked)
        guard let edit = ListEditing.newline(text: text, selection: selection) else { return nil }
        var units = Array(text.utf16)
        units.replaceSubrange(edit.range, with: Array(edit.replacement.utf16))
        return mark(String(decoding: units, as: UTF16.self), edit.selection)
    }

    @Test func returnContinuesTheList() {
        #expect(newline("- milk|") == "- milk\n- |")
        #expect(newline("  * [x] done|") == "  * [x] done\n  * [ ] |")
        #expect(newline("9) nine|") == "9) nine\n10) |")
        #expect(newline("- spl|it") == "- spl\n- |it")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(newline("- a\n- |") == "- a\n|")
        #expect(newline("- [ ] |") == "|")
    }

    @Test func returnOutsideAListIsPlain() {
        #expect(newline("text|") == nil)
        #expect(newline("-| a") == nil)
    }

    // MARK: - Key table

    @Test func theKeyTableMatchesObsidian() {
        #expect(ListEditShortcut.command(for: .init(key: "l", command: true, shift: true)) == .toggleBulletList)
        #expect(ListEditShortcut.command(for: .init(key: "l", command: true, option: true)) == .cycleListChecklist)
        #expect(ListEditShortcut.command(for: .init(key: "l", option: true)) == .toggleCheckbox)
        #expect(ListEditShortcut.command(for: .init(key: "l", command: true)) == nil)
    }
}
