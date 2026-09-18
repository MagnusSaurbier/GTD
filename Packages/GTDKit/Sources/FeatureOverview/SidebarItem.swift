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

    public var title: String {
        switch self {
        case .inbox: Copy.inbox
        case .next: Copy.next
        case .backlog: Copy.backlog
        case .waiting: Copy.waiting
        case .maybe: Copy.maybe
        case .projects: Copy.project
        case .deferred: Copy.deferLabel
        case .review: Copy.weeklyReview
        case .routines: Copy.routine
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

    /// `⌘1…⌘7` — the first seven items only (STYLEGUIDE §4.5).
    public var shortcutNumber: Int? {
        switch self {
        case .inbox: 1
        case .next: 2
        case .backlog: 3
        case .waiting: 4
        case .maybe: 5
        case .projects: 6
        case .deferred: 7
        default: nil
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
