import Foundation
import GTDModel
import DesignSystem

/// What the project detail's area picker (P6, R-7) shows, decided outside SwiftUI so it is
/// tested on Linux. Mirrors `ProjectPickerContent`: a **chip** for the current area (confirmed)
/// or an unset `Area` chip that opens the list — never an invented "No area" row inside the list
/// itself (STYLEGUIDE forbids that label; `ProjectDetailModel.setArea(nil)` is reached only
/// through the distinct `ProjectsCopy.removeFromArea` action, and only once a project has an
/// area to remove).
public enum AreaPickerContent {

    /// The chip's title and state for the project's current area.
    public static func chip(area: Area?) -> (title: String, state: ChipState) {
        guard let area else { return (Copy.unsetChipTitle(Copy.area), .unset) }
        return (area.title, .confirmed)
    }

    /// `GTDError` → what the picker shows inline (never swallowed with `try?`, ARCHITECTURE §6).
    public static func message(for error: any Error) -> String {
        switch error as? GTDError {
        case let .titleCollision(title): ProjectsCopy.areaNameTaken(title)
        case .notFound: ProjectsCopy.areaGone
        default: "\(error)"
        }
    }
}
