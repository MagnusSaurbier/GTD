import Foundation

/// Strings and symbols the Mac shell needs that `DesignSystem.Copy` / `DesignSystem.Symbols`
/// do not (yet) carry. Same pattern as `DesignSystem.Copy`: feature code never inlines a
/// user-facing string or an SF Symbol name, it references a constant.
///
/// These are Mac-shell-local on purpose: `DesignSystem.Copy` carries the fixed vocabulary of
/// STYLEGUIDE §6.2, and none of the strings below is part of it. If `Copy` ever grows them (or
/// becomes `LocalizedStringResource`s backed by `Resources/Localizable.xcstrings`), this file
/// folds into it without changing a call site.
enum OverviewCopy {

    // Sidebar section names: the plural forms of STYLEGUIDE §4.1, which `Copy` has only in
    // the singular (§6.2 fixed vocabulary).
    static let projects = "Projects"
    static let routines = "Routines"

    // Shell chrome
    static let go = "Go"
    static let filter = "Filter"
    static let filterPlaceholder = "Filter by title"
    static let vaultIssues = "Vault issues"
    static let calendar = "Calendar"
    static let newCapture = "New capture"
    /// `⌘⇧N`/`⌘⇧S` menu items (STYLEGUIDE §4.5, fixed — not one of inbox processing's rebindable
    /// single keys): move the action open in the detail column to Next / Someday.
    static let moveToNext = "Move to Next"
    static let moveToSomeday = "Move to Someday"
    static let status = "Status"
    static let context = "Context"
    static let time = "Time"

    // Detail view
    static let titlePlaceholder = "Action title"
    static let noSelectionTitle = "Nothing selected"
    static let noSelectionBody = "Pick an action from the list."
    static let missingActionTitle = "Action is gone"
    static let missingActionBody = "It was completed, trashed or renamed elsewhere."
    static let closedActionBody = "It was completed or moved to Trash."
    static let more = "More"
    static let notSaved = "Not saved"
    static let titleTaken = "Another action already has that title."

    /// `12 items` — the count under a list's title when it is filtered.
    static func matches(_ count: Int) -> String { count == 1 ? "1 match" : "\(count) matches" }

    static let emptyListBody = "Process your inbox, or move something here."
    static let emptyFilterTitle = "No match"
    static let emptyFilterBody = "Nothing here fits this filter."
}

/// SF Symbols the shell needs beyond `DesignSystem.Symbols` (STYLEGUIDE §7 is exhaustive for
/// concepts; these are plain chrome affordances, so they stay out of the §7 map).
enum OverviewSymbols {
    static let filter = "line.3.horizontal.decrease.circle"
    static let issues = "exclamationmark.triangle"
    static let collapse = "chevron.down"
    static let expand = "chevron.up"
    static let calendar = "calendar"
    static let placeholder = "square.dashed"
    static let more = "ellipsis.circle"
}
