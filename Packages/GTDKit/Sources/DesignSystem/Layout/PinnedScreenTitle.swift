#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// A screen's headline, pinned on top of the page (issue #33). The navigation bar's large
    /// title scrolls with the list: it rubber-bands down on a pull and collapses on a scroll, and
    /// on the Next tab it slid over the filter chips. On the iPhone the headline is therefore
    /// its own top bar, in `Typo.screenTitle`, and the bar's inline title is removed so the
    /// name is not shown twice. The navigation title stays set, so a pushed page's back button
    /// still reads it. Mac: plain `.navigationTitle`, the window title.
    ///
    /// Apply it outside a screen's own top `safeAreaBar` (the Next chips): the outer bar sits
    /// above the inner one, so the headline stays on top.
    public func pinnedScreenTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .safeAreaBar(edge: .top, spacing: 0) {
                Text(title)
                    .font(Typo.screenTitle.bold())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.bottom, Spacing.s)
                    .accessibilityAddTraits(.isHeader)
            }
        #else
        navigationTitle(title)
        #endif
    }
}
#endif
