#if canImport(SwiftUI)
import SwiftUI
import Testing
@testable import DesignSystem

/// What a `NoteEditor` answers SwiftUI's size probes with (`NoteText.fittingSize`).
@MainActor
struct NoteSizingTests {

    /// A stand-in for TextKit: a 1 000-point line wrapped at `width`, 20 pt per line.
    private func measure(_ width: CGFloat) -> CGFloat { ceil(1_000 / width) * 20 }

    /// A real width is measured and reported as it is.
    @Test func aRealWidthIsMeasuredAsProposed() {
        #expect(NoteText.fittingSize(proposedWidth: 555, measure: measure)
                == CGSize(width: 555, height: 40))
        #expect(NoteText.fittingSize(proposedWidth: 572, measure: measure)
                == CGSize(width: 572, height: 40))
    }

    /// The `0` probe asks for the minimum width. The answer used to be the view's current
    /// width, so a field once laid out 572 pt wide claimed it could not get narrower: with a
    /// legacy scroller the detail column flipped between 555 and 572 pt every pass until AppKit
    /// crashed the app (2026-09-27, a Next action with long checklist lines).
    @Test func theMinimumWidthIsZeroWhateverTheFieldWasLaidOutAt() {
        let size = NoteText.fittingSize(proposedWidth: 0, measure: measure)
        #expect(size.width == 0)
        #expect(size.height == measure(NoteText.unproposedWidth))
    }

    /// `nil` and infinity ask for the ideal size: a fixed width, not the current frame.
    @Test func theIdealWidthIsFixed() {
        let expected = CGSize(width: NoteText.unproposedWidth,
                              height: measure(NoteText.unproposedWidth))
        #expect(NoteText.fittingSize(proposedWidth: nil, measure: measure) == expected)
        #expect(NoteText.fittingSize(proposedWidth: .infinity, measure: measure) == expected)
    }
}
#endif
