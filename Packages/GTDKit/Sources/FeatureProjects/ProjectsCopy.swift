import Foundation

/// Strings this target needs that `DesignSystem.Copy` does not carry, plus the wording of its
/// own refusals. Same pattern as `FeatureOverview.OverviewCopy` / `FeatureWaiting.WaitingCopy`:
/// feature code never inlines a user-facing string.
enum ProjectsCopy {
    /// R-7's area picker (P6, STYLEGUIDE): clears `ProjectDetailModel.setArea` to `nil`. Not a
    /// "No area" option inside the picker's list — a distinct action, reached only when the
    /// project currently has an area.
    static let removeFromArea = "Remove from area"

    /// `GTDError.titleCollision` from `setArea` — the destination area already holds a project
    /// of this name (R-7).
    static func areaNameTaken(_ title: String) -> String {
        "Another project named \"\(title)\" is already in that area."
    }

    /// `GTDError.notFound` from `setArea` — the area disappeared (another device removed it).
    static let areaGone = "That area is gone."

    // Projects tree folder rows (#67) — VoiceOver value and hint.
    static let folderExpanded = "Expanded"
    static let folderCollapsed = "Collapsed"
    static let expandFolder = "Shows the projects in this folder"
    static let collapseFolder = "Hides the projects in this folder"
}
