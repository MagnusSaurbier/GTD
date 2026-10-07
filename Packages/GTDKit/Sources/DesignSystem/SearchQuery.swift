#if canImport(SwiftUI)
import SwiftUI

/// The ⌘F filter text of the enclosing window, so the Mac shell's filter bar reaches the list it
/// filters, whichever feature owns that list (#5, #98). `""` means "no filter" — also the value
/// outside the Mac shell.
private struct SearchQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    public var searchQuery: String {
        get { self[SearchQueryKey.self] }
        set { self[SearchQueryKey.self] = newValue }
    }
}

extension View {
    /// Hands the window's ⌘F filter text to the lists below it.
    public func searchQuery(_ query: String) -> some View {
        environment(\.searchQuery, query)
    }
}
#endif
