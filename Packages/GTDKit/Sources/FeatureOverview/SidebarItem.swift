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

    /// Sections that show the generic action list/detail pair; the others route to the feature
    /// that owns them (T20–T24, T27).
    public var showsCalendarStrip: Bool {
        switch self {
        case .review, .routines: false
        default: true
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
