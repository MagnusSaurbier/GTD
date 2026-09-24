#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import DesignSystem

/// One row of the Next list / chase section: the completion circle, then the row's text and
/// badges as **one opening target**.
///
/// Why not `DesignSystem.ActionRow`: that row keeps its badges on the title's line, so two
/// badges squeeze a long title into a narrow, truncated column (walkthrough P12), and it nests
/// its completion `Button` inside whatever the host uses to open the row (M2). Here
/// - the title gets the full row width (up to three lines) and the badges drop to their own line
///   whenever title + badges do not fit side by side (`ViewThatFits`);
/// - the circle and the opening target are siblings, never nested, so both stay reliable.
///
/// No decisions live here — what to show comes from `NextListModel`.
struct NextRow: View {
    let action: Action
    /// What the row's title line shows — `action.title` for a plain Next row, or
    /// `NextListModel.chaseTitle(for:)` (`Chase: <who> — <what>`) for a chase row.
    let title: String
    /// `NextListModel.metaParts(for:)` — project, contexts, time bucket.
    let metaParts: [String]
    let badges: [BadgeContent]
    /// `NextListModel.spokenLabel(for:)`.
    let spokenLabel: String
    let onOpen: () -> Void
    let onComplete: () -> Void

    /// Width of the completion circle; with `Spacing.m` it is where the row's text starts, and
    /// therefore where the row separator starts (`separatorInset`).
    static let circleSize: CGFloat = 22
    static var separatorInset: CGFloat { circleSize + Spacing.m }

    /// `.increased` inside a system-selected (emphasised) row on the Mac: custom ink colours
    /// would stay dark on the accent selection, so the text falls back to the hierarchical
    /// styles the system inverts for us.
    @Environment(\.backgroundProminence) private var prominence
    @State private var isDrawingCheck = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            completionControl
            openTarget
        }
        .padding(.vertical, Spacing.rowVertical)
    }

    // MARK: - Opening target

    @ViewBuilder private var openTarget: some View {
        #if os(macOS)
        // The Mac list is a `List(selection:)`: the arrow keys select the row and the selection
        // opens it. The click needs its own gesture since the rows became drag sources (E3):
        // the drag source takes the mouse-down before the list's selection sees it. The
        // element still has to *say* it is a button and be activatable from VoiceOver.
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
        #else
        Button(action: onOpen) {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        #endif
    }

    @ViewBuilder private var content: some View {
        if shownBadges.isEmpty {
            textBlock(titleLines: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                // Fits only when the whole title sits on one line next to the badges.
                HStack(alignment: .top, spacing: Spacing.s) {
                    textBlock(titleLines: 1)
                    Spacer(minLength: Spacing.s)
                    badgeLine
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    textBlock(titleLines: 3)
                    badgeLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func textBlock(titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typo.body)
                .foregroundStyle(isProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.ink))
                .lineLimit(titleLines)
                .multilineTextAlignment(.leading)
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(Typo.meta)
                    .foregroundStyle(isProminent ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.textSecondary))
                    .lineLimit(titleLines == 1 ? 1 : 2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// Badges never shrink: a squeezed capsule wraps its text letter by letter.
    private var badgeLine: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(shownBadges.enumerated()), id: \.offset) {
                Badge($0.element).fixedSize()
            }
        }
    }

    private var shownBadges: [BadgeContent] {
        Array(badges.prefix(SignalPresentation.maxBadgesPerRow))
    }

    private var isProminent: Bool { prominence == .increased }
    private var metaLine: String { Copy.metaLine(metaParts) }

    // MARK: - Completion circle (STYLEGUIDE §3.3 — same behaviour as `ActionRow`)

    /// Tap draws the checkmark in `signalDone` over `MotionTiming.checkDraw` with one `.success`
    /// haptic, then the actual completion (and the row's collapse) follows.
    private var completionControl: some View {
        Button {
            guard !isDrawingCheck else { return }
            withAnimation(Motion.standard) { isDrawingCheck = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + MotionTiming.checkDraw) {
                onComplete()
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
                } else if action.status == .inProgress {
                    Circle().fill(Color.ink).frame(width: 11, height: 11)
                }
            }
            .frame(width: Self.circleSize, height: Self.circleSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isDrawingCheck)
        .accessibilityLabel("\(Copy.done) \(title)")
    }
}
#endif
