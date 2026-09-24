#if canImport(SwiftUI)
import SwiftUI

/// The app version in the bottom-right corner of the window (Mac) and of the tab content
/// (iPhone): `Typo.counter` in `textTertiary`, so it reads only when looked for. Every build
/// carries the version of the issue it came from (`docs/TICKETS.md`), which is what makes the
/// stamp worth a corner — "which version is this?" is answered without opening Settings.
///
/// Draws nothing when the bundle carries no version rather than inventing one.
public struct VersionStamp: View {
    private let version: AppVersion

    public init(version: AppVersion = .current) {
        self.version = version
    }

    public var body: some View {
        if !version.stampLabel.isEmpty {
            Text(version.stampLabel)
                .font(Typo.counter)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .accessibilityLabel(version.spokenLabel)
                // Never in the way of what is underneath: no hit testing, no focus.
                .allowsHitTesting(false)
                .accessibilityIdentifier("version-stamp")
        }
    }
}
#endif
