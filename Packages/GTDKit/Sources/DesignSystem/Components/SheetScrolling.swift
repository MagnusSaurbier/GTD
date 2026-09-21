#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// For a `Form` presented as a sheet. macOS' default form style (`.columns`) lays every row
    /// out at full height, never scrolls, and turns a text field's title into a left-column
    /// label — a long picker runs off the bottom of the sheet. `.grouped` scrolls and is iOS'
    /// default already, so iOS is unchanged.
    func sheetFormStyle() -> some View {
        formStyle(.grouped).scrollingSheetFrame()
    }

    /// For a `List` or grouped `Form` presented as a Mac sheet: scrolling content has no
    /// intrinsic height, so give the sheet a size to open at (`SheetMetrics`). No-op on iOS,
    /// where detents size the sheet.
    func scrollingSheetFrame() -> some View {
        #if os(macOS)
        frame(
            minWidth: SheetMetrics.minWidth, idealWidth: SheetMetrics.idealWidth,
            minHeight: SheetMetrics.minHeight, idealHeight: SheetMetrics.idealHeight)
        #else
        self
        #endif
    }
}

/// Rows inside a content-sized sheet (a plain `VStack`, no `List`): drawn inline while they fit
/// under `maxHeight`, scrolling once they do not — so a project with thirty steps cannot push the
/// sheet's buttons off the screen.
public struct OverflowScroll<Content: View>: View {
    private let maxHeight: CGFloat
    private let spacing: CGFloat
    private let content: Content

    public init(
        maxHeight: CGFloat = SheetMetrics.inlineRowsMaxHeight,
        spacing: CGFloat = Spacing.l,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeight = maxHeight
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        .frame(maxHeight: maxHeight)
        // Without this the frame grows to whatever the sheet offers, up to `maxHeight`, and a
        // two-row list leaves a gap under it. Its ideal height is the rows' own, capped.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
