#if canImport(SwiftUI)
import SwiftUI
import Foundation
import GTDModel

/// Small capsule badge (STYLEGUIDE §3.2). Text comes from `SignalPresentation` — never invented
/// at the call site. Background = signal colour @ 18 % (light) / 28 % (dark); the label stays
/// `.primary` so contrast holds in both modes.
public struct Badge: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: BadgeContent

    /// The capsule grows with the text (STYLEGUIDE §8: Dynamic Type to AX3 without loss of
    /// function). It used to be a hard `height: 20`, which clipped `16 days old` at the
    /// accessibility sizes.
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 20

    public init(_ content: BadgeContent) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol = content.symbol {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            Text(content.text)
                .foregroundStyle(content.step == .neutral ? Color.textSecondary : Color.ink)
        }
        .font(Typo.badge)
        .padding(.horizontal, Spacing.s)
        .frame(minHeight: height)
        .background(background)
        .clipShape(Radius.chipShape)
        // Never squeezed: in a narrow column a badge used to wrap letter by letter into a
        // vertical capsule. It keeps its ideal size and the row's title gives way instead.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private var tint: Color { .signal(Self.style(content.step)) }

    private var background: Color {
        content.step == .neutral ? .fillQuiet : tint.opacity(colorScheme == .dark ? 0.28 : 0.18)
    }

    static func style(_ step: SignalStep) -> SignalStepStyle {
        switch step {
        case .neutral: .neutral
        case .aging: .aging
        case .attention: .attention
        case .overdue: .overdue
        }
    }
}

/// The row used in every action list on both platforms (STYLEGUIDE §3.3).
///
/// ```
/// (○)  Title of the action, up to two lines                 [16d] [due Thu]
///      Project name · mac · phone · ≤30 min
/// ```
/// Missing values are omitted — never "No project", never "0 min".
public struct ActionRow: View {
    private let action: Action
    private let projectTitle: String?
    private let badges: [BadgeContent]
    private let onComplete: (() -> Void)?

    public init(
        action: Action,
        projectTitle: String? = nil,
        badges: [BadgeContent] = [],
        onComplete: (() -> Void)? = nil
    ) {
        self.action = action
        self.projectTitle = projectTitle
        self.badges = badges
        self.onComplete = onComplete
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            completionControl
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            // One VoiceOver element for the row's text, with the `·` separators spoken as
            // pauses instead of "middle dot" (STYLEGUIDE §8).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTitleAndMeta)
            Spacer(minLength: Spacing.s)
            ForEach(Array(badges.prefix(SignalPresentation.maxBadgesPerRow).enumerated()), id: \.offset) {
                Badge($0.element)
            }
        }
        .padding(.vertical, Spacing.rowVertical)
    }

    /// STYLEGUIDE §3.3: tap draws the checkmark in `signalDone` over `MotionTiming.checkDraw`
    /// with one `.success` haptic, then the actual completion (and the row's collapse) follows —
    /// the visual reward plays before the data changes, not after.
    @State private var isDrawingCheck = false

    private var completionControl: some View {
        CompletionCircle(
            isDrawingCheck: $isDrawingCheck,
            isInProgress: action.status == .inProgress,
            onComplete: onComplete)
    }

    /// `Project name · mac · phone · ≤30 min` — project first, contexts as plain lowercase text.
    private var metaLine: String {
        Copy.metaLine(metaParts)
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let projectTitle { parts.append(projectTitle) }
        parts.append(contentsOf: action.contexts)
        if let bucket = action.timeBucket { parts.append("\(Copy.timeBucket(bucket)) min") }
        return parts
    }

    private var spokenTitleAndMeta: String {
        Copy.spoken([action.title] + metaParts)
    }
}

/// List-item variant of `ActionRow` (STYLEGUIDE §3.3 "List items"): completion circle + title
/// only — no second line, no badges, no age, because a list item is not a commitment and cannot
/// go stale.
public struct ListItemRow: View {
    private let item: ListItem
    private let onComplete: (() -> Void)?

    public init(item: ListItem, onComplete: (() -> Void)? = nil) {
        self.item = item
        self.onComplete = onComplete
    }

    @State private var isDrawingCheck = false

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            CompletionCircle(isDrawingCheck: $isDrawingCheck, isInProgress: false, onComplete: onComplete)
            Text(item.title)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
        }
        .padding(.vertical, Spacing.rowVertical)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
    }
}

/// The completion control shared by `ActionRow` and `ListItemRow` (STYLEGUIDE §3.3): tap draws
/// the checkmark in `signalDone` over `MotionTiming.checkDraw` with one `.success` haptic before
/// the actual completion follows — the visual reward plays before the data changes.
private struct CompletionCircle: View {
    @Binding var isDrawingCheck: Bool
    let isInProgress: Bool
    let onComplete: (() -> Void)?

    var body: some View {
        Button {
            guard !isDrawingCheck else { return }
            withAnimation(Motion.standard) { isDrawingCheck = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + MotionTiming.checkDraw) {
                onComplete?()
            }
        } label: {
            ZStack {
                Circle().strokeBorder(isDrawingCheck ? Color.signalDone : Color.textTertiary, lineWidth: 1.5)
                if isDrawingCheck {
                    Circle().fill(Color.signalDone)
                    Image(systemName: Symbols.done)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.inkInverse)
                        .font(.system(size: 13, weight: .medium))
                } else if isInProgress {
                    Circle().fill(Color.ink).frame(width: 11, height: 11)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(onComplete == nil)
        .sensoryFeedback(.success, trigger: isDrawingCheck)
        .accessibilityLabel(Copy.done)
    }
}

/// A projects-list row (STYLEGUIDE §3.4, E4): name + `stalled` badge, then
/// `<n> active · <m> steps left`, then up to three of its active actions.
public struct ProjectRow: View {
    private let row: Rules.ProjectRow
    private let today: Day
    private let onOpenAction: ((NoteID) -> Void)?

    public init(
        row: Rules.ProjectRow,
        today: Day = Day.today(),
        onOpenAction: ((NoteID) -> Void)? = nil
    ) {
        self.row = row
        self.today = today
        self.onOpenAction = onOpenAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(row.project.title).font(Typo.body).foregroundStyle(Color.ink)
                if row.isStalled {
                    Badge(SignalPresentation.badge(
                        for: Signal(kind: .stalled, step: .attention), today: today))
                }
            }
            // The row's own heading reads as one phrase; the action buttons below stay separate
            // elements because each of them is a target (STYLEGUIDE §8).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.spoken(
                [row.project.title, row.isStalled ? Copy.stalled : "", countsLine]))
            Text(countsLine)
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)      // already in the header's label
            ForEach(row.activeActions.prefix(3), id: \.id) { action in
                Button {
                    onOpenAction?(action.id)
                } label: {
                    Text(action.title)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.l)
            }
        }
        .padding(.vertical, Spacing.rowVertical)
    }

    /// `2 active · 5 steps left`.
    private var countsLine: String {
        Copy.projectCounts(active: row.activeActions.count, remainingSteps: row.remainingSteps)
    }
}
#endif
