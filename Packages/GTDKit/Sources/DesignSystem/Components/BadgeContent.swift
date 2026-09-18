import Foundation
import GTDModel

/// The four states of a `Chip` (STYLEGUIDE §3.1). Shape carries state, never hue.
public enum ChipState: Sendable, Equatable, Hashable, CaseIterable {
    /// Available, not chosen.
    case unset
    /// The app proposes this. Dashed outline + `sparkles`. **Never written to a file
    /// until the user confirms it.**
    case suggested
    /// The user decided. Ink fill.
    case confirmed
    case disabled
}

/// What a `Badge` shows. Platform-free so the §2.2 table can be unit-tested (T12 acceptance).
public struct BadgeContent: Sendable, Equatable, Hashable {
    public var text: String
    public var symbol: String?
    public var step: SignalStep
    /// Read by VoiceOver in full words (STYLEGUIDE §8).
    public var accessibilityLabel: String

    public init(text: String, symbol: String?, step: SignalStep, accessibilityLabel: String) {
        self.text = text
        self.symbol = symbol
        self.step = step
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Turns the semantic `Signal`s from `GTDModel/Rules` into badge text and symbols.
/// This is the only place that knows the wording of STYLEGUIDE §2.2 — agents never invent it.
public enum SignalPresentation {

    /// At most two badges per row, highest step first (STYLEGUIDE §3.2).
    public static let maxBadgesPerRow = 2

    public static func badges(for signals: [Signal], today: Day) -> [BadgeContent] {
        signals
            .sorted { $0.step > $1.step }
            .prefix(maxBadgesPerRow)
            .map { badge(for: $0, today: today) }
    }

    public static func badge(for signal: Signal, today: Day) -> BadgeContent {
        switch signal.kind {
        case let .untouched(days):
            BadgeContent(
                text: DateText.age(days: days),
                symbol: signal.step == .attention ? Symbols.staleAttention : Symbols.aging,
                step: signal.step,
                accessibilityLabel: "Untouched, \(DateText.spelledAge(days: days))")

        case let .followUpSoon(day):
            BadgeContent(
                text: "follow up \(DateText.short(day, today: today))",
                symbol: Symbols.waiting,
                step: signal.step,
                accessibilityLabel: "Follow up \(DateText.spelled(day, today: today))")

        case let .chase(days):
            BadgeContent(
                text: "chase · \(DateText.age(days: days))",
                symbol: Symbols.chase,
                step: signal.step,
                accessibilityLabel: days == 0
                    ? "Chase, follow-up due today"
                    : "Chase, follow-up \(days) days overdue")

        case let .dueSoon(day):
            BadgeContent(
                text: "due \(DateText.short(day, today: today))",
                symbol: Symbols.due,
                step: signal.step,
                accessibilityLabel: "Due \(DateText.spelled(day, today: today))")

        case .dueToday:
            BadgeContent(
                text: "due today",
                symbol: Symbols.dueToday,
                step: signal.step,
                accessibilityLabel: "Due today")

        case let .overdue(days):
            BadgeContent(
                text: "\(DateText.age(days: days)) overdue",
                symbol: Symbols.overdue,
                step: signal.step,
                accessibilityLabel: days == 1 ? "1 day overdue" : "\(days) days overdue")

        case .returnedFromDefer:
            BadgeContent(
                text: "back",
                symbol: Symbols.deferred,
                step: signal.step,
                accessibilityLabel: "Came back today")

        case .stalled:
            BadgeContent(
                text: "stalled",
                symbol: Symbols.stalled,
                step: signal.step,
                accessibilityLabel: "Stalled, no open action")

        case let .cap(count, cap):
            BadgeContent(
                text: "\(count)/\(cap)",
                symbol: nil,
                step: signal.step,
                accessibilityLabel: "\(count) of \(cap) in Next")

        case let .inboxAge(days):
            BadgeContent(
                text: DateText.age(days: days),
                symbol: Symbols.aging,
                step: signal.step,
                accessibilityLabel: DateText.spelledAge(days: days))
        }
    }
}
