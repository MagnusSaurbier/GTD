import Foundation
import GTDModel
import GTDAppCore
import DesignSystem

/// Sidebar sections of the Mac window (E3). Settings is a stock `Settings` scene (T40),
/// not a sidebar item. Owned by T25.
public enum SidebarItem: Hashable, Sendable, CaseIterable {
    case inbox
    case next
    /// #87 — the In progress board: in progress | agent | review.
    case inProgress
    case someday
    case waiting
    case lists
    case projects
    case deferred
    case review
    case routines

    /// The counted sections, in the order of STYLEGUIDE §4.1 (In progress right under Next,
    /// #87) — they form the first sidebar group and own `⌘1…⌘n`.
    public static let counted: [SidebarItem] = [
        .inbox, .next, .inProgress, .someday, .waiting, .lists, .projects, .deferred,
    ]

    /// The second sidebar group: the two guided flows.
    public static let flows: [SidebarItem] = [.review, .routines]

    public var title: String {
        switch self {
        case .inbox: Copy.inbox
        case .next: Copy.next
        case .inProgress: Copy.inProgress
        case .someday: Copy.someday
        case .waiting: Copy.waiting
        case .lists: Copy.lists
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
        case .inProgress: Symbols.inProgress
        case .someday: Symbols.someday
        case .waiting: Symbols.waiting
        case .lists: Symbols.listBullet
        case .projects: Symbols.projects
        case .deferred: Symbols.deferred
        case .review: Symbols.weeklyReview
        case .routines: Symbols.routineGeneric
        }
    }

    /// `⌘1…⌘n` — the counted sections only (STYLEGUIDE §4.5).
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
        case .someday: .someday
        default: nil
        }
    }

    /// E3 — what a row dropped on this section asks for (`MovePlan`). `nil` for the sections
    /// nothing can be dropped on: the inbox is processed in forced order (I1), and the flows
    /// are not categories. Lists asks which list, like the inbox's `More…` sheet.
    public var moveDestination: MoveDestination? {
        switch self {
        case .next: .next
        case .inProgress: .inProgress
        case .someday: .someday
        case .waiting: .waiting
        case .deferred: .deferred
        case .projects: .projects
        case .lists: .lists
        case .inbox, .review, .routines: nil
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
        case .next, .someday, .waiting, .deferred: OverviewMacCopy.pickAnAction
        case .inProgress: OverviewMacCopy.pickAnAction
        case .lists: OverviewMacCopy.pickAnItem
        case .projects: OverviewMacCopy.pickAProject
        case .inbox: OverviewMacCopy.inboxIsProcessed
        case .review, .routines: nil
        }
    }

    /// L5 — the single `Lists` sidebar row counts open items across **every** list.
    public func count(_ counts: Rules.SidebarCounts) -> Int? {
        switch self {
        case .inbox: counts.inbox
        case .next: counts.next
        case .inProgress: counts.inProgress
        case .someday: counts.someday
        case .waiting: counts.waiting
        case .lists: counts.lists
        case .projects: counts.projects
        case .deferred: counts.deferred
        default: nil
        }
    }
}
