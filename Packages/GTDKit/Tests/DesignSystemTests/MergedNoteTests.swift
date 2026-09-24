import Testing
import DesignSystem

/// The path the conflict sheet's title field turns into.
@Suite struct MergedNoteTests {
    @Test func aTitleBecomesAFileInTheNotesFolder() {
        #expect(MergedNote.path(folder: "Actions", title: "Call the bank") == "Actions/Call the bank.md")
        #expect(MergedNote.path(folder: "", title: "Call the bank") == "Call the bank.md")
    }

    @Test func whitespaceIsTrimmedAndASlashCannotMakeAFolder() {
        #expect(MergedNote.path(folder: "Actions", title: "  A/B \n") == "Actions/A-B.md")
    }

    @Test func anEmptyTitleIsNoPath() {
        #expect(MergedNote.path(folder: "Actions", title: "   ") == nil)
    }
}
