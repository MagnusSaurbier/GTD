import Foundation
import Testing
@testable import DesignSystem

/// `View.scrollingSheetFrame()` hands these straight to `frame(minWidth:idealWidth:…)`; SwiftUI
/// reports "contradictory frame constraints" at run time, and picks a size of its own, when an
/// ideal is below its minimum.
struct SheetMetricsTests {

    @Test func idealSizeIsNeverBelowTheMinimum() {
        #expect(SheetMetrics.idealWidth >= SheetMetrics.minWidth)
        #expect(SheetMetrics.idealHeight >= SheetMetrics.minHeight)
    }

    /// An inline run of rows that scrolls must leave room for the sheet's title and buttons.
    @Test func inlineRowsStayShorterThanTheSmallestSheet() {
        #expect(SheetMetrics.inlineRowsMaxHeight < SheetMetrics.minHeight)
    }

    /// The card cap must leave a content-sized sheet room for its counter, action bar and legend
    /// on the smallest Mac window the app opens in, yet be tall enough that a card whose fields
    /// fit today never starts scrolling.
    @Test func cardCapLeavesRoomForTheSheetChrome() {
        #expect(SheetMetrics.cardMaxHeight >= SheetMetrics.idealHeight)
        #expect(SheetMetrics.cardMaxHeight > SheetMetrics.inlineRowsMaxHeight)
        #expect(SheetMetrics.cardMinHeight < SheetMetrics.cardMaxHeight)
    }

    /// The window-relative cap: unknown window → the plain maximum; a tall window → the
    /// maximum; a 600 pt window → what is left after the sheet's chrome; a tiny window →
    /// the floor, never less.
    @Test func cardCapFollowsTheWindowHeight() {
        #expect(SheetMetrics.cardCap(forWindowHeight: nil) == SheetMetrics.cardMaxHeight)
        #expect(SheetMetrics.cardCap(forWindowHeight: 2000) == SheetMetrics.cardMaxHeight)
        let cap600: CGFloat = 600 - SheetMetrics.cardSheetChrome
        #expect(SheetMetrics.cardCap(forWindowHeight: 600) == cap600)
        #expect(SheetMetrics.cardCap(forWindowHeight: 300) == SheetMetrics.cardMinHeight)
    }
}
