import Foundation
import Observation
import GTDModel

/// What the right-hand column shows (E3).
public enum OverviewDetail: Hashable, Sendable {
    case action(NoteID)
    case project(NoteID)

    public var noteID: NoteID {
        switch self {
        case let .action(id): id
        case let .project(id): id
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

    public func open(action id: NoteID) { detail = .action(id) }

    public func open(project id: NoteID) { detail = .project(id) }

    /// Follows a rename: the note keeps its place in the detail column under its new `NoteID`.
    public func replace(_ old: NoteID, with new: NoteID) {
        switch detail {
        case let .action(id) where id == old: detail = .action(new)
        case let .project(id) where id == old: detail = .project(new)
        default: break
        }
    }

    /// Drops a detail selection whose note no longer exists in `snapshot`.
    public func prune(against snapshot: VaultSnapshot) {
        switch detail {
        case let .action(id) where snapshot.action(id) == nil: detail = nil
        case let .project(id) where snapshot.project(id) == nil: detail = nil
        default: break
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
