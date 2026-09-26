import Foundation

/// Strings `FeatureLists` needs that `DesignSystem.Copy` does not (yet) carry — same pattern as
/// `FeatureOverview.OverviewCopy`: feature code never inlines a user-facing string, it references
/// a constant here or in `DesignSystem.Copy`.
enum ListsCopy {
    static let notesPlaceholder = "Notes (optional)"
    static let titlePlaceholder = "Item title"
    static let missingItemTitle = "Item is gone"
    static let missingItemBody = "It was completed, trashed or made into an action elsewhere."
    static let notSaved = "Not saved"
    static let titleTaken = "Another item already has that title."
    static let makeAction = "Make action"
    static let addItem = "Add item"
    static let add = "Add"
    static let newItemPlaceholder = "New item"
    /// `Add to Read` — the add sheet's heading, spelled with the list's name like the undo toast.
    static func addTo(_ list: String) -> String { "Add to \(list)" }
    static let emptyListsTitle = "No lists yet"
    static let emptyListsBody = "Lists are created from Settings, or by filing a capture to one."

    /// `12 items` / `1 item` — a list section's open count on Mac.
    static func itemCount(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
}
