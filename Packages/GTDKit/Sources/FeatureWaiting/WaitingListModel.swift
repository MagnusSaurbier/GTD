import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Waiting-for (deferred items included — a deferral is a who-less waiting item, #86) and the
/// calendar-strip data (W2, D1, D3). Plain and unit-testable — **no SwiftUI**. Owned by T23.
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

    /// Days since the item was last touched — the "waiting since N days" column. Uses the file
    /// modification date (ARCHITECTURE §5's definition of "untouched": a status change rewrites
    /// the file), falling back to `created` for notes `GTDVault` hasn't stamped yet.
    public func waitingSinceDays(_ action: Action) -> Int {
        guard let reference = action.modified ?? action.created else { return 0 }
        return today.days(since: Day(reference))
    }

    /// A waiting item's follow-up date has passed — the row is overdue (W2).
    public func isOverdue(_ action: Action) -> Bool {
        guard let followUp = action.followUpDate else { return false }
        return followUp <= today
    }

    /// The signal step that tints the row's follow-up date chip: the `chase` signal's step once
    /// the follow-up date has passed, `nil` (plain chip) before. Taken from `Rules.signals`, so
    /// the chip and the `chase` badge next to it can never disagree (walkthrough M10).
    public func followUpSignal(for action: Action) -> SignalStep? {
        Rules.signals(for: action, today: today).first {
            if case .chase = $0.kind { true } else { false }
        }?.step
    }

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    // MARK: - Row / title text (W1/D39's optional who)

    /// The waiting row's meta line: `who` (when present) then the "waiting since" age, never a
    /// dangling separator when `who` is empty/nil (D39 — who is optional, STYLEGUIDE "no lying
    /// defaults": an absent value is simply omitted, not printed as an empty dash). Pure, so it
    /// is testable without SwiftUI (ARCHITECTURE §5).
    public func metaParts(for action: Action) -> [String] {
        WaitingListModel.rowMeta(who: action.waitingFor, ageText: DateText.age(days: waitingSinceDays(action)))
    }

    static func rowMeta(who: String?, ageText: String) -> [String] {
        var parts: [String] = []
        if let who, !who.isEmpty { parts.append(who) }
        parts.append(ageText)
        return parts
    }

    /// The action's current `who` + follow-up, for `WaitingInfoSheet(initial:)` when editing.
    public func waitingInfo(for action: Action) -> WaitingInfo? { action.waiting }

    /// The suggested "bump" follow-up date — `today` + 7 days — offered as a **suggested**
    /// (dashed) chip. Never written until the user confirms it (§1 "no lying defaults").
    public var suggestedBump: Day { WaitingInfo.suggestedFollowUp(from: today) }

    /// The `WaitingInfo` a "chase done → bump" (or any date picked in the row's calendar)
    /// confirms: the same `who`, a new follow-up date.
    ///
    /// W1/D39 — the who is **optional**, so a waiting item without one bumps like any other.
    /// This used to return `nil` for a missing who and the row's chip then silently dropped the
    /// date the user had just picked: on a real vault, where M2 imported every waiting item with
    /// no who at all, no follow-up date could be set from the list (user report, 2026-09-24).
    /// A blank who is normalised away, so no empty `waitingFor:` line is written.
    public func bumped(_ action: Action, to date: Day) -> WaitingInfo {
        let who = action.waitingFor?.trimmingCharacters(in: .whitespaces)
        return WaitingInfo(who: (who?.isEmpty ?? true) ? nil : who, followUp: date)
    }

    /// Markers for the Mac calendar strip (D3), grouped per day, `today` first.
    public func timeline(days: Int) -> [(day: Day, entries: [Rules.TimelineEntry])] {
        let to = today.adding(days: days - 1)
        let all = Rules.timeline(model.snapshot, from: today, to: to)
        return (0..<days).map { offset in
            let day = today.adding(days: offset)
            return (day: day, entries: all.filter { $0.day == day })
        }
    }

    /// Defer, due and follow-up dates already in the past — piled on the left edge of the strip
    /// instead of being lost off the front of the 14-day window (D3).
    public var overduePile: [Rules.TimelineEntry] {
        Rules.timeline(model.snapshot, from: today.adding(days: -365), to: today.adding(days: -1))
    }

    /// The signal step a calendar-strip marker should be tinted with, or `nil` for a plain,
    /// untinted symbol. Per STYLEGUIDE §3.10, a marker "takes a signal colour only when §2.2
    /// says so": `due` and follow-up markers use the same thresholds as their row badges. A
    /// deferral's marker (a who-less follow-up, #86) is never tinted: the only signal it gets,
    /// `back`, is itself a neutral badge, not a colour.
    public func signalStep(for entry: Rules.TimelineEntry, policy: StalenessPolicy = .default) -> SignalStep? {
        let delta = entry.day.days(since: today)
        switch entry.kind {
        case .due:
            if delta < 0 { return .overdue }
            if delta == 0 { return .attention }
            if delta <= policy.dueSoonDays { return .aging }
            return nil
        case .followUp:
            if isWhoLessFollowUp(entry) { return nil }
            if delta <= 0 { return .attention }
            if delta <= policy.followUpSoonDays { return .aging }
            return nil
        case .deferred:
            return nil
        }
    }

    private func isWhoLessFollowUp(_ entry: Rules.TimelineEntry) -> Bool {
        model.snapshot.action(entry.action)?.isWhoLessWaiting ?? false
    }

    /// "Recent who" values offered as suggestions in `WaitingInfoSheet`, most recently seen
    /// first (`waiting` is already sorted by staleness, so this is oldest-waiting-first — good
    /// enough as a first cut; there is no separate "last used" timestamp to sort by).
    public var recentWho: [String] {
        var seen: [String] = []
        for action in waiting {
            guard let who = action.waitingFor, !seen.contains(who) else { continue }
            seen.append(who)
        }
        return Array(seen.prefix(5))
    }
}
