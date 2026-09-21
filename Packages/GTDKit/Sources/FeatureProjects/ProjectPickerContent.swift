import Foundation
import GTDModel
import DesignSystem

/// What `ProjectPicker` shows, decided outside SwiftUI so it can be tested on Linux.
///
/// The picker is a **chip**: the current project in the confirmed state, or an unset `Project`
/// chip (the chip draws the `plus`) that opens the list. It is never an empty labelled section
/// (walkthrough 2026-09-19, P6), and an action with no project never reads "No project"
/// (STYLEGUIDE §1 "no lying defaults").
public enum ProjectPickerContent {

    /// The chip's title and state for `selection`.
    ///
    /// A project that is on hold / someday / done is still named — the action belongs to it
    /// whatever its status. A link to a note the snapshot no longer has falls back to the file
    /// name, so a dangling link stays visible instead of looking unset.
    public static func chip(
        selection: NoteID?, in snapshot: VaultSnapshot
    ) -> (title: String, state: ChipState) {
        guard let selection else { return (Copy.unsetChipTitle(Copy.project), .unset) }
        let title = snapshot.projects.first { $0.id == selection }?.title ?? selection.title
        return (title, .confirmed)
    }

    /// The rows of the list: every active project, plus the currently selected one when it is
    /// not active (otherwise the list could not show — or clear — the current choice).
    public static func options(selection: NoteID?, in snapshot: VaultSnapshot) -> [Project] {
        snapshot.projects.filter { $0.status == .active || $0.id == selection }
    }

    /// Tapping the selected row clears it; tapping another row selects that one.
    public static func toggled(_ project: NoteID, from selection: NoteID?) -> NoteID? {
        selection == project ? nil : project
    }
}
