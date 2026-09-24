#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

/// STYLEGUIDE §4.4 — where `NoteLayoutManager` draws a task's box, on the TextKit 1 stack the
/// editor uses (macOS only; the iOS stack is the same class).
@MainActor
struct NoteLayoutTests {

    /// A `NoteTextView` on the editor's TextKit 1 stack, laid out, caret at the end.
    private func editor(_ text: String) -> (NoteTextView, NoteLayoutManager, NSTextContainer) {
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = NoteTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        view.storage = storage
        view.isRichText = false
        view.string = text
        view.restyle()
        layout.ensureLayout(for: container)
        view.setSelectedRange(NSRange(location: storage.length, length: 0))
        return (view, layout, container)
    }

    /// Return at the end of a task: the task above keeps a box of real width at the line
    /// start (TextKit put it zero-wide at the end of the line above, so it was not drawn).
    @Test func theTaskAboveANewTaskKeepsItsBox() {
        let (view, layout, container) = editor("# What?\n- [ ] one\n- [ ] two")
        let coordinator = NoteEditor.Coordinator(text: .constant(""))
        view.delegate = coordinator  // restyles on text and selection changes, as in the app
        view.insertNewline(nil)
        #expect(view.string == "# What?\n- [ ] one\n- [ ] two\n- [ ] ")
        layout.ensureLayout(for: container)
        let storage = view.textStorage!

        var boxes: [CGRect] = []
        for location in [10, 20, 30] {
            #expect(storage.attribute(.noteCheckbox, at: location, effectiveRange: nil) as? Bool == false)
            boxes.append(layout.rectFor(NSRange(location: location, length: 3), in: container, origin: .zero))
        }
        for box in boxes {
            #expect(box.width > 5)
            #expect(box.minX == 0)
        }
        #expect(boxes[0].minY < boxes[1].minY && boxes[1].minY < boxes[2].minY)
    }
}
#endif
