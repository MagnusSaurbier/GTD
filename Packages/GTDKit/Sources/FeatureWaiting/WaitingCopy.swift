import Foundation

/// Strings this target needs that `DesignSystem.Copy` does not carry in the right form, and the
/// one decision its two Mac lists share. Same pattern (and the same reason) as
/// `FeatureOverview.OverviewCopy`: feature code never inlines a user-facing string.
///
/// `Copy.deferLabel` is the **verb/field** label ("Defer") used on the date chip; the screen that
/// lists deferred items is called "Deferred" everywhere it is named — the sidebar, the empty
/// detail column and the window title (walkthrough 2026-09-19).
enum WaitingCopy {
    static let deferredTitle = "Deferred"
}
