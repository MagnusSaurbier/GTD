import Foundation

/// The three-step warm scale plus a neutral step (STYLEGUIDE §2.1/§2.2).
/// A step is *semantics*; `DesignSystem` decides what colour and symbol it gets.
public enum SignalStep: Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case neutral
    case aging
    case attention
    case overdue
}

/// What the signal is about, with the number or date the badge needs. No strings, no colours —
/// `DesignSystem` turns these into badge text and symbols (STYLEGUIDE §2.2).
public enum SignalKind: Sendable, Equatable, Hashable {
    /// Action untouched for this many days.
    case untouched(days: Int)
    /// Waiting item whose follow-up is within the "soon" window.
    case followUpSoon(Day)
    /// Waiting item whose follow-up date has passed — it becomes a chase item in Next.
    case chase(days: Int)
    /// `due` within the "soon" window.
    case dueSoon(Day)
    case dueToday
    case overdue(days: Int)
    /// A deferral (a who-less waiting item, #86) whose date arrived in the last 24 h — the item
    /// just came back into Next.
    case returnedFromDefer
    /// Active project with zero open actions.
    case stalled
    /// Next list at or above the cap.
    case cap(count: Int, cap: Int)
    /// Inbox item older than the inbox threshold.
    case inboxAge(days: Int)
}

/// One semantic signal about an entity.
public struct Signal: Sendable, Equatable, Hashable {
    public var kind: SignalKind
    public var step: SignalStep

    public init(kind: SignalKind, step: SignalStep) {
        self.kind = kind
        self.step = step
    }
}

/// Every threshold in one place (STYLEGUIDE §2.2, §10 — "first guesses, tune after two reviews").
/// Views and `DesignSystem` never hard-code these numbers.
public struct StalenessPolicy: Sendable, Equatable {
    /// Action untouched longer than this ⇒ `aging`.
    public var actionAgingDays: Int
    /// Action untouched longer than this ⇒ `attention`.
    public var actionAttentionDays: Int
    /// Inbox item older than this ⇒ `aging`.
    public var inboxAgingDays: Int
    /// Waiting follow-up this close ⇒ `aging`.
    public var followUpSoonDays: Int
    /// `due` this close ⇒ `aging`.
    public var dueSoonDays: Int
    /// A deferral back in Next shows the `back` badge for this many days (#86).
    public var returnedFromDeferDays: Int
    /// Done actions older than this are archive candidates (A5).
    public var archiveAfterDays: Int

    public init(
        actionAgingDays: Int = 14,
        actionAttentionDays: Int = 30,
        inboxAgingDays: Int = 7,
        followUpSoonDays: Int = 2,
        dueSoonDays: Int = 3,
        returnedFromDeferDays: Int = 1,
        archiveAfterDays: Int = 30
    ) {
        self.actionAgingDays = actionAgingDays
        self.actionAttentionDays = actionAttentionDays
        self.inboxAgingDays = inboxAgingDays
        self.followUpSoonDays = followUpSoonDays
        self.dueSoonDays = dueSoonDays
        self.returnedFromDeferDays = returnedFromDeferDays
        self.archiveAfterDays = archiveAfterDays
    }

    public static let `default` = StalenessPolicy()
}
