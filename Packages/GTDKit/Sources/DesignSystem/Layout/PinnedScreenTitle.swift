#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// A screen's title, pinned on top of the page. iPhone: the small inline title between the
    /// navigation bar's buttons (#36), so the room a large title took goes to the content; an
    /// inline title neither scrolls, rubber-bands nor collapses with the list (#33). Mac: plain
    /// `.navigationTitle`, the window title.
    public func pinnedScreenTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle(title)
        #endif
    }
}
#endif
