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
}
