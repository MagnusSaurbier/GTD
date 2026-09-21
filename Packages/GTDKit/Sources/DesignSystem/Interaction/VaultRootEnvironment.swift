#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    /// Absolute path of the vault folder, for "Open in Obsidian" (`GTDAppCore.ObsidianLink`).
    /// The app shell sets it once the vault is open; feature targets never touch the file
    /// system themselves. `nil` on fixtures and before a vault is picked — then there is no link.
    @Entry public var vaultRootPath: String? = nil
}
#endif
