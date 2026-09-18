#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Which field of the card has the keyboard. While one of them is focused, swipes and the
/// letter/arrow keys are off (STYLEGUIDE §3.6).
enum CardField: Hashable {
    case text
    case why
    case what
    case title
}

/// The inbox card (STYLEGUIDE §3.5): meta line, raw captured text, `Why?`, `What?`, chips.
/// The card does not scroll internally; beyond six lines the raw text collapses behind `Show all`.
struct InboxCardView: View {
    @Bindable var session: InboxSession
    @FocusState.Binding var focus: CardField?
    /// Non-nil while a drag is past its threshold — drives the destination label and the tint.
    let dragTarget: CardTarget?
    let translation: CGSize
    let shake: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rotation: Double {
        guard !reduceMotion else { return 0 }
        let fraction = max(min(translation.width / 400, 1), -1)
        return fraction * DragThresholds.maxRotationDegrees
    }

    var body: some View {
        ItemCard {
            metaLine
            rawText
            field(
                label: Copy.why,
                placeholder: Copy.whyPlaceholder,
                text: $session.draft.why,
                field: .why)
            whatSection
            titleRow
            chips
        }
        .offset(x: translation.width, y: translation.height)
        .rotationEffect(.degrees(rotation))
        .modifier(ShakeEffect(travel: shake))
        .overlay { tintOverlay }
        .overlay(alignment: dragAlignment) { destinationLabel }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(CardTarget.allCases) { target in
                Button(target.title) { Task { await session.choose(target) } }
            }
            Button(Copy.undo) { Task { await session.undo() } }
        }
    }

    // MARK: 1. Meta line

    private var metaLine: some View {
        HStack(spacing: Spacing.s) {
            if let current = session.current {
                Text(InboxCopy.captureStamp(current.created, today: session.today))
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(
                Array(SignalPresentation.badges(for: session.currentSignals, today: session.today)
                    .enumerated()),
                id: \.offset
            ) { badge in
                Badge(badge.element)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 2. Raw captured text

    @ViewBuilder private var rawText: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField(
                InboxCopy.rawTextPlaceholder,
                text: $session.draft.text,
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.cardText)
                .foregroundStyle(Color.ink)
                .lineLimit(focus == .text ? nil : 6)
                .focused($focus, equals: .text)
            if isRawTextLong, focus != .text {
                Button(InboxCopy.showAll) { session.sheet = .fullText }
                    .font(Typo.meta)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.gtdAccent)
            }
        }
    }

    private var isRawTextLong: Bool {
        session.draft.text.components(separatedBy: "\n").count > 6
            || session.draft.text.count > 320
    }

    // MARK: 3./4. Why? and What?

    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: CardField
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .focused($focus, equals: field)
        }
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(Copy.what)
                    .font(Typo.sectionHeader)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                // A text button: `⋯`-style list icons are not in the icon map (STYLEGUIDE §7),
                // and the guide forbids inventing symbols.
                Button(InboxCopy.checklist) {
                    session.draft.what = ChecklistText.isChecklist(session.draft.what)
                        ? ChecklistText.asPlainText(session.draft.what)
                        : ChecklistText.asChecklist(session.draft.what)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
            }
            TextField(Copy.whatPlaceholder, text: $session.draft.what, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .focused($focus, equals: .what)
                .onChange(of: session.draft.what) { _, newValue in
                    let formatted = ChecklistText.autoFormat(newValue)
                    if formatted != newValue { session.draft.what = formatted }
                }
            // A2 — a second checkbox means this is probably a project.
            if session.draft.suggestsProject {
                Button {
                    session.sheet = .project
                } label: {
                    Label(Copy.turnIntoProject, systemImage: Symbols.projects)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.gtdAccent)
            }
        }
    }

    /// The action note's title, derived from the first line of `What?` and editable before filing.
    @ViewBuilder private var titleRow: some View {
        if !session.draft.effectiveTitle.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(InboxCopy.titleLabel)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                TextField(
                    InboxCopy.titlePlaceholder,
                    text: Binding(
                        get: { session.draft.effectiveTitle },
                        set: {
                            session.draft.title = $0
                            session.draft.titleWasEdited = true
                        }))
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .focused($focus, equals: .title)
            }
        }
    }

    // MARK: 5. Chips

    private var chips: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(InboxCopy.contextGroupLabel)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                ContextChipGroup(contexts: session.contexts, selection: $session.draft.contexts)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(InboxCopy.timeGroupLabel)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                TimeBucketChipGroup(selection: $session.draft.timeBucket)
            }
            FlowLayout {
                DateValueChip(
                    label: InboxCopy.addDefer,
                    value: $session.draft.deferDate,
                    today: session.today)
                DateValueChip(
                    label: InboxCopy.addDue,
                    value: $session.draft.due,
                    today: session.today)
                Chip(
                    projectChipTitle,
                    state: session.draft.project == nil ? .unset : .confirmed,
                    symbol: session.draft.project == nil ? "plus" : nil
                ) {
                    session.sheet = .project
                }
            }
        }
    }

    private var projectChipTitle: String {
        guard let id = session.draft.project else { return "+ \(InboxCopy.addProject)" }
        return session.snapshot.project(id)?.title ?? id.title
    }

    // MARK: Drag feedback (STYLEGUIDE §3.6)

    private var dragAlignment: Alignment {
        guard let direction = dragTarget?.swipe else { return .center }
        switch direction {
        case .right: return .trailing
        case .left: return .leading
        case .up: return .top
        case .down: return .bottom
        }
    }

    @ViewBuilder private var tintOverlay: some View {
        if let dragTarget {
            Radius.cardShape.fill(tint(for: dragTarget))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var destinationLabel: some View {
        if let dragTarget {
            Label(dragTarget.title, systemImage: dragTarget.symbol)
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
                .padding(Spacing.l)
                .allowsHitTesting(false)
        }
    }

    private func tint(for target: CardTarget) -> Color {
        switch target {
        case .next: Color.accentWash
        case .trash: Color.signalOverdue.opacity(CardTarget.trashTintOpacity)
        default: Color.fillQuiet
        }
    }
}

/// The 6 pt shake of STYLEGUIDE §3.6 — validation never opens an alert. Skipped under
/// Reduce Motion (the caller simply never changes `travel`).
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: sin(travel * .pi * 3) * 6, y: 0))
    }
}
#endif
