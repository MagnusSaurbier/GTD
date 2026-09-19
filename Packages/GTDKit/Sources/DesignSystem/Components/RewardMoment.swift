#if canImport(SwiftUI)
import SwiftUI

/// The exactly-two reward moments (STYLEGUIDE §5): inbox zero and routine/weekly-review
/// complete. Same shape both times — a bouncing symbol, one `.success` haptic, a title and a
/// stats line — so nothing here invents a third. No confetti, streaks or praise copy.
public struct RewardMoment: View {
    private let symbol: String
    private let showsCheckBadge: Bool
    private let title: String
    private let detail: String

    @State private var hasAppeared = false

    public init(symbol: String, showsCheckBadge: Bool = false, title: String, detail: String) {
        self.symbol = symbol
        self.showsCheckBadge = showsCheckBadge
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: Spacing.l) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.ink)
                    // System symbol effects already adapt to Reduce Motion (HIG); no manual guard needed.
                    .symbolEffect(.bounce, value: hasAppeared)
                if showsCheckBadge {
                    Image(systemName: Symbols.done)
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.signalDone)
                        .background(Circle().fill(Color.surface))
                        .offset(x: 4, y: 4)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text(title).font(Typo.sectionHeader).foregroundStyle(Color.ink)
                Text(detail).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.xxl)
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}

public extension RewardMoment {
    /// STYLEGUIDE §5.1 — last inbox card leaves: `tray` bounces, `signalDone` checkmark badge,
    /// `Inbox zero`, `14 processed · 6 min`.
    static func inboxZero(processed: Int, minutes: Int) -> RewardMoment {
        RewardMoment(
            symbol: Symbols.inbox,
            showsCheckBadge: true,
            title: Copy.emptyInboxTitle,
            detail: Copy.processedSummary(processed: processed, minutes: minutes))
    }

    /// STYLEGUIDE §5.2 — a routine finishes: `checkmark.circle` bounces, `<Routine> done`,
    /// `9 of 11 steps`.
    static func routineComplete(routine: String, done: Int, total: Int) -> RewardMoment {
        RewardMoment(
            symbol: Symbols.done,
            title: Copy.routineDone(routine),
            detail: Copy.stepsSummary(done: done, total: total))
    }

    /// STYLEGUIDE §5.2 — the weekly review finishes: `checkmark.circle` bounces, `Review
    /// complete`, `9 of 11 steps`.
    static func reviewComplete(done: Int, total: Int) -> RewardMoment {
        RewardMoment(
            symbol: Symbols.done,
            title: Copy.reviewComplete,
            detail: Copy.stepsSummary(done: done, total: total))
    }
}
#endif
