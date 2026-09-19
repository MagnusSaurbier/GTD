import Foundation
import GTDModel
import GTDAppCore
import DesignSystem

/// Sidebar sections of the Mac window (E3). Settings is a stock `Settings` scene (T40),
/// not a sidebar item. Owned by T25.
public enum SidebarItem: Hashable, Sendable, CaseIterable {
    case inbox
    case next
    case backlog
    case waiting
    case maybe
    case projects
    case deferred
    case review
    case routines

    /// The counted sections, in the order of STYLEGUIDE §4.1 — they form the first sidebar group
    /// and own `⌘1…⌘7`.
    public static let counted: [SidebarItem] = [
        .inbox, .next, .backlog, .waiting, .maybe, .projects, .deferred,
    ]

    /// The second sidebar group: the two guided flows.
    public static let flows: [SidebarItem] = [.review, .routines]

    public var title: String {
        switch self {
        case .inbox: Copy.inbox
        case .next: Copy.next
        case .backlog: Copy.backlog
        case .waiting: Copy.waiting
        case .maybe: Copy.maybe
        case .projects: OverviewCopy.projects
        case .deferred: OverviewCopy.deferred
        case .review: Copy.weeklyReview
        case .routines: OverviewCopy.routines
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: Symbols.inbox
        case .next: Symbols.next
        case .backlog: Symbols.backlog
        case .waiting: Symbols.waiting
        case .maybe: Symbols.maybe
        case .projects: Symbols.projects
        case .deferred: Symbols.deferred
        case .review: Symbols.weeklyReview
        case .routines: Symbols.routineGeneric
        }
    }

    /// `⌘1…⌘7` — the counted sections only (STYLEGUIDE §4.5).
    public var shortcutNumber: Int? {
        SidebarItem.counted.firstIndex(of: self).map { $0 + 1 }
    }

    /// The section `⌘<n>` selects, or `nil` when no section has that number.
    public init?(shortcutNumber: Int) {
        let index = shortcutNumber - 1
        guard SidebarItem.counted.indices.contains(index) else { return nil }
        self = SidebarItem.counted[index]
    }

    /// The action status this section lists, if it is a plain status list.
    public var listedStatus: ActionStatus? {
        switch self {
        case .backlog: .backlog
        case .maybe: .maybe
        default: nil
        }
    }

    /// D3 — the calendar strip is docked only under the lists whose items are *dated*: Next
    /// (due), Waiting (follow-up) and Deferred (defer). Everywhere else it was dead space.
    public var showsCalendarStrip: Bool {
        switch self {
        case .next, .waiting, .deferred: true
        default: false
        }
    }

    /// The guided flows have no list/detail pair: their view spans the content *and* the detail
    /// column (sidebar + one wide column) instead of being squeezed into the list column.
    public var spansDetailColumn: Bool {
        switch self {
        case .review, .routines: true
        default: false
        }
    }

    /// What the empty detail column says — it names what this section's list holds. `nil` for
    /// sections that have no detail column, or nothing to open in it (the inbox is processed in
    /// forced order, I1).
    public var emptyDetailBody: String? {
        switch self {
        case .next, .backlog, .waiting, .maybe, .deferred: OverviewMacCopy.pickAnAction
        case .projects: OverviewMacCopy.pickAProject
        case .inbox: OverviewMacCopy.inboxIsProcessed
        case .review, .routines: nil
        }
    }

    public func count(_ counts: Rules.SidebarCounts) -> Int? {
        switch self {
        case .inbox: counts.inbox
        case .next: counts.next
        case .backlog: counts.backlog
        case .waiting: counts.waiting
        case .maybe: counts.maybe
        case .projects: counts.projects
        case .deferred: counts.deferred
        default: nil
        }
    }
}
