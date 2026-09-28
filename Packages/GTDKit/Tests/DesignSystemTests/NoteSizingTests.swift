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
    /// A fractional proposal is measured at the whole point below it, so a live resize does not
    /// produce a new answer for every rounding difference.
    @Test func fractionalWidthsAreMeasuredAtWholePoints() {
        var measured: [CGFloat] = []
        let size = NoteText.fittingSize(proposedWidth: 555.4) { width in
            measured.append(width); return 40 }
        #expect(measured == [555])
        #expect(size.width == 555.4)
    }

    /// A resize moves the width a few times per turn: answers pass through unchanged.
    @Test func theGuardLeavesOrdinaryLayoutAlone() {
        var guarded = NoteText.SizeGuard()
        for width in [600, 590, 580] as [CGFloat] {
            let size = CGSize(width: width, height: measure(width))
            #expect(guarded.settle(size, proposedWidth: width) == size)
        }
        #expect(!guarded.tripped)
    }

    /// The 2026-09-28 crash: the width flips 555 ↔ 572 within one turn. Past the limit every
    /// answer carries the tallest height of the turn, so the height stops following the width
    /// and the loop can settle instead of AppKit aborting.
    @Test func aFlippingWidthGetsOneHeight() {
        let tall: (CGFloat) -> CGFloat = { $0 < 560 ? 60 : 40 }
        var guarded = NoteText.SizeGuard()
        var answers: [CGFloat] = []
        for index in 0..<40 {
            let width: CGFloat = index.isMultiple(of: 2) ? 555 : 572
            answers.append(guarded.settle(CGSize(width: width, height: tall(width)),
                                          proposedWidth: width).height)
        }
        #expect(guarded.tripped)
        #expect(answers.suffix(20).allSatisfy { $0 == 60 })

        guarded.endTurn()
        #expect(!guarded.tripped)
        #expect(guarded.settle(CGSize(width: 572, height: 40), proposedWidth: 572).height == 40)
    }

    /// Probes (`0`, `nil`, infinity) are not layout and never count.
    @Test func probesDoNotCount() {
        var guarded = NoteText.SizeGuard()
        for index in 0..<50 {
            _ = guarded.settle(CGSize(width: CGFloat(index), height: 10), proposedWidth: 0)
            _ = guarded.settle(CGSize(width: 320, height: 10), proposedWidth: nil)
        }
        #expect(!guarded.tripped)
    }

    /// Once tripped, the minimum and ideal answers stop moving too: the 2026-09-27 loop ran
    /// through the minimum width, not the height.
    @Test func aTrippedGuardHoldsTheProbeAnswers() {
        var guarded = NoteText.SizeGuard()
        _ = guarded.settle(CGSize(width: 572, height: 40), proposedWidth: 0)
        _ = guarded.settle(CGSize(width: 320, height: 90), proposedWidth: nil)
        for index in 0..<30 {
            let width: CGFloat = index.isMultiple(of: 2) ? 555 : 572
            _ = guarded.settle(CGSize(width: width, height: 40), proposedWidth: width)
        }
        #expect(guarded.tripped)
        #expect(guarded.settle(CGSize(width: 555, height: 60), proposedWidth: 0)
                == CGSize(width: 572, height: 40))
        #expect(guarded.settle(CGSize(width: 320, height: 99), proposedWidth: .infinity)
                == CGSize(width: 320, height: 90))
    }
}
#endif
