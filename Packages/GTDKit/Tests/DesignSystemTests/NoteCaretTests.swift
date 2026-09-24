#if canImport(SwiftUI)
import SwiftUI
import Testing
@testable import DesignSystem

/// Where the caret goes when the text of a `NoteEditor` is replaced from outside the view.
@MainActor
struct NoteCaretTests {

    /// The inbox card turns a typed `- ` into `- [ ] `: the caret was at the end and must end up
    /// after the marker, not inside the hidden markup (2026-09-24 user report).
    @Test func aBulletBecomingACheckboxKeepsTheCaretAfterTheMarker() {
        #expect(NoteText.caret(2, from: "- ", to: "- [ ] ") == 6)
        #expect(NoteText.caret(8, from: "first\n- \n", to: "first\n- [ ] \n") == 12)
    }

    @Test func aCaretBeforeTheChangeStays() {
        #expect(NoteText.caret(3, from: "abc\n- ", to: "abc\n- [ ] ") == 3)
        #expect(NoteText.caret(0, from: "- ", to: "- [ ] ") == 0)
    }

    @Test func aCaretAfterTheChangeMovesWithIt() {
        #expect(NoteText.caret(8, from: "- x\nrest", to: "- [ ] x\nrest") == 12)
        // A deletion before the caret pulls it back.
        #expect(NoteText.caret(10, from: "- [ ] x\nrest", to: "x\nrest") == 4)
    }

    @Test func aCaretInsideTheReplacedStretchGoesToItsEnd() {
        #expect(NoteText.caret(3, from: "abcdef", to: "aXYf") == 3)
        #expect(NoteText.caret(4, from: "hello world", to: "hi world") == 2)
    }

    @Test func outOfRangeCaretsAreClamped() {
        #expect(NoteText.caret(99, from: "ab", to: "abc") == 3)
        #expect(NoteText.caret(-1, from: "ab", to: "xab") == 1)
        #expect(NoteText.caret(2, from: "ab", to: "") == 0)
    }
}
#endif
