#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    /// The icons picked per list (`GTDConfig.listIcons`). The app shell passes the synced config
    /// down, so every place that draws a list glyph uses `Symbols.list(named:icons:)` with it.
    @Entry public var listIcons: [String: String] = [:]
}
#endif
