import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Waiting-for, deferred items and the calendar-strip data (W2, D1, D3). Plain and
/// unit-testable — **no SwiftUI**. Owned by T23.
@MainActor
@Observable
public final class WaitingListModel {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var today: Day { model.today() }

    /// Sorted by staleness: the longest-overdue follow-up first (W2).
    public var waiting: [Action] { Rules.waitingList(model.snapshot, today: today) }

    /// Deferred items grouped by return date: this week, then later (D1).
    public var deferredThisWeek: [Action] {
        Rules.deferredList(model.snapshot, today: today)
            .filter { ($0.deferDate?.days(since: today) ?? .max) <= 7 }
    }

    public var deferredLater: [Action] {
        Rules.deferredList(model.snapshot, today: today)
            .filter { ($0.deferDate?.days(since: today) ?? .max) > 7 }
    }

    /// Days since the item entered `waiting` — the "waiting since N days" column.
    public func waitingSinceDays(_ action: Action) -> Int {
        guard let created = action.created else { return 0 }
        return today.days(since: Day(created))
    }

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    /// Markers for the 14-day calendar strip (D3), grouped per day.
    public func timeline(days: Int) -> [(day: Day, entries: [Rules.TimelineEntry])] {
        let to = today.adding(days: days - 1)
        let all = Rules.timeline(model.snapshot, from: today, to: to)
        return (0..<days).map { offset in
            let day = today.adding(days: offset)
            return (day: day, entries: all.filter { $0.day == day })
        }
    }

    /// Follow-ups that are already overdue — piled on the left edge of the strip.
    public var overduePile: [Rules.TimelineEntry] {
        Rules.timeline(model.snapshot, from: today.adding(days: -365), to: today.adding(days: -1))
    }

    /// "Recent who" values offered as suggestions in `WaitingInfoSheet`.
    public var recentWho: [String] {
        var seen: [String] = []
        for action in waiting {
            guard let who = action.waitingFor, !seen.contains(who) else { continue }
            seen.append(who)
        }
        return Array(seen.prefix(5))
    }
}
