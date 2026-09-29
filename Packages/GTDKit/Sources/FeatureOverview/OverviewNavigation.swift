import Foundation
import Observation
import GTDModel
import GTDAppCore

/// What the right-hand column shows (E3).
public enum OverviewDetail: Hashable, Sendable {
    case action(NoteID)
    case project(NoteID)
    /// T10 — the `Lists` sidebar row's detail column: one list item's title + notes editor.
    case listItem(NoteID)

    public var noteID: NoteID {
        switch self {
        case let .action(id): id
        case let .project(id): id
        case let .listItem(id): id
        }
    }
}

/// Selection and window-level state of the Mac shell. Deliberately free of SwiftUI so the
/// routing rules are unit-tested on Linux (ARCHITECTURE §5 "Platform guards").
///
/// `OverviewView()` creates its own instance. The app shell (T40) that also wants the menu-bar
/// `OverviewCommands` creates one, keeps it alive and hands it to both.
@MainActor
@Observable
public final class OverviewNavigation {
    /// The selected sidebar section. Never `nil` — the window always shows a list.
    public var selection: SidebarItem {
        didSet {
            guard oldValue != selection else { return }
            detail = nil
            query = ""
            isSearching = false
        }
    }

    /// The note in the detail column, `nil` when nothing is selected.
    public var detail: OverviewDetail?

    /// `⌘F` filter-as-you-type over the titles in the current list. Reset when the section changes.
    public var query: String = ""
    /// True while the filter field should hold focus (`⌘F`).
    public var isSearching = false

    /// `⌘N` — capture is owned by the app shell (C1: it writes through `GTDVault.InboxWriter`,
    /// which feature targets must not import). The shell observes this flag and resets it.
    public var isCaptureRequested = false

    /// `⌘I` / the *Process inbox* button — the processing flow runs full-window (I1).
    public var isProcessingInbox = false

    /// The vault-issue list (`snapshot.issues`) presented as a sheet.
    public var isIssuesPresented = false

    /// The calendar strip docked at the bottom of the middle column (D3), collapsible.
    public var isCalendarExpanded = true

    public init(selection: SidebarItem = .next) {
        self.selection = selection
    }

    /// Selecting a section from the sidebar (or the menu bar).
    public func select(_ item: SidebarItem) { selection = item }

    /// `⌘1…⌘7`. Returns false when no section carries that number.
    @discardableResult
    public func select(shortcutNumber: Int) -> Bool {
        guard let item = SidebarItem(shortcutNumber: shortcutNumber) else { return false }
        selection = item
        return true
    }

    /// The action in the detail column — what the list column highlights as selected.
    public var openAction: NoteID? {
        if case let .action(id) = detail { return id }
        return nil
    }

    /// The project in the detail column — what the Projects list highlights as selected (M2).
    public var openProject: NoteID? {
        if case let .project(id) = detail { return id }
        return nil
    }

    /// The list item in the detail column — what a `ListsSectionsView` section highlights (T10).
    public var openListItem: NoteID? {
        if case let .listItem(id) = detail { return id }
        return nil
    }

    public func open(action id: NoteID) { detail = .action(id) }

    public func open(project id: NoteID) { detail = .project(id) }

    public func open(listItem id: NoteID) { detail = .listItem(id) }

    /// The action detail's "Open project" (#72): the Projects section, with that project in the
    /// detail column and highlighted in the list. Section first — changing it clears `detail`.
    public func show(project id: NoteID) {
        selection = .projects
        detail = .project(id)
    }

    /// Follows a rename: the note keeps its place in the detail column under its new `NoteID`.
    public func replace(_ old: NoteID, with new: NoteID) {
        switch detail {
        case let .action(id) where id == old: detail = .action(new)
        case let .project(id) where id == old: detail = .project(new)
        case let .listItem(id) where id == old: detail = .listItem(new)
        default: break
        }
    }

    /// Consumes one snapshot update: a renamed note keeps the detail column under its new
    /// `NoteID`, a note that really left the vault loses it.
    ///
    /// Remap **then** prune, in one call, because the snapshot alone cannot tell the two apart —
    /// a renamed note's old id is as absent from it as a deleted one's
    /// (`GTDAppCore.NavigationRemap`).
    public func apply(snapshot: VaultSnapshot, renames: RenameMap = .empty) {
        switch detail {
        case let .action(id):
            detail = NavigationRemap
                .selection(id, renames: renames) { snapshot.action($0) != nil }
                .map(OverviewDetail.action)
        case let .project(id):
            detail = NavigationRemap
                .selection(id, renames: renames) { snapshot.project($0) != nil }
                .map(OverviewDetail.project)
        case let .listItem(id):
            detail = NavigationRemap
                .selection(id, renames: renames) { snapshot.listItem($0) != nil }
                .map(OverviewDetail.listItem)
        case nil:
            break
        }
    }

    public func beginSearch() {
        isSearching = true
    }

    public func endSearch() {
        isSearching = false
        query = ""
    }
}
