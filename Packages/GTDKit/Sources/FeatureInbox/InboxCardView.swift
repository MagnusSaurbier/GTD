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
/// Beyond six lines the raw text collapses behind `Show all`. The card itself never scrolls; on
/// iPhone `InboxSessionView` puts it in a `ScrollView` so the software keyboard cannot squeeze
/// it — which is also why every text field is `fixedSize` vertically (it may never collapse)
/// and carries its `CardField` as `id` (the scroll view brings the focused one into view).
struct InboxCardView: View {
    @Bindable var session: InboxSession
    @FocusState.Binding var focus: CardField?
    /// Non-nil while a drag is past its threshold — drives the destination label and the tint.
    let dragTarget: InboxExit?
    let translation: CGSize
    let shake: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped when Return submits the title (O1): a wrapping field keeps the typed line break
    /// on screen unless it is rebuilt from the (single-line) draft.
    @State private var titleGeneration = 0

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
        // STYLEGUIDE §3.6 — "VoiceOver exposes every exit of the current step as a custom
        // action". The list and its wording are the session's (`InboxExit.title`), never the
        // view's.
        .accessibilityActions {
            ForEach(session.exits, id: \.self) { exit in
                Button(exit.title) { Task { await session.take(exit) } }
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
                "",
                text: $session.draft.text,
                prompt: Self.prompt(InboxCopy.rawTextPlaceholder),
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.cardText)
                .foregroundStyle(Color.ink)
                .lineLimit(focus == .text ? nil : 6)
                // Never compressed: without this the last line loses its descenders.
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: .text)
                .accessibilityLabel(InboxCopy.rawTextPlaceholder)
            if isRawTextLong, focus != .text {
                Button(InboxCopy.showAll) { session.sheet = .fullText }
                    .font(Typo.meta)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.gtdAccent)
            }
        }
        .id(CardField.text)
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
            TextField("", text: text, prompt: Self.prompt(placeholder), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
        }
        .id(field)
    }

    /// A placeholder must never read as an entered value (no lying defaults): it is tertiary,
    /// the value is `ink`. macOS otherwise draws the prompt of a plain field in the text colour.
    private static func prompt(_ placeholder: String) -> Text {
        Text(placeholder).foregroundStyle(Color.textTertiary)
    }

    /// Folds typed or pasted line breaks out of the title: a Return submits, pasted lines join
    /// with one space. Text without a line break passes through untouched (no trimming while
    /// the person is still typing) — mirrors `ActionEditModel.titleInput`.
    private static func titleInput(_ raw: String) -> (text: String, submitted: Bool) {
        guard raw.contains(where: \.isNewline) else { return (raw, false) }
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (lines.joined(separator: " "), true)
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
            TextField(
                "",
                text: $session.draft.what,
                prompt: Self.prompt(Copy.whatPlaceholder),
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .focused($focus, equals: .what)
                .accessibilityLabel(Copy.what)
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
        .id(CardField.what)
    }

    /// R-4 — the note's title *is* the capture text (editable in place): the field edits the
    /// capture itself, and the reducer names the file after its first line.
    ///
    /// `axis: .vertical` keeps a long capture (a full sentence) fully visible instead of
    /// truncating with an ellipsis (O1); Return still submits — it never inserts a line break —
    /// by folding a typed/pasted newline out of the text and dropping focus, the same move
    /// `ActionDetailView`'s title field makes. `titleGeneration` forces the field to rebuild
    /// from the (newline-free) draft afterwards, or the typed line break stays on screen.
    @ViewBuilder private var titleRow: some View {
        if !session.draft.text.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(InboxCopy.titleLabel)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                TextField(
                    "",
                    text: Binding(
                        get: { session.draft.text },
                        set: { newValue in
                            let input = Self.titleInput(newValue)
                            session.draft.text = input.text
                            if input.submitted {
                                focus = nil
                                titleGeneration += 1
                            }
                        }),
                    prompt: Self.prompt(InboxCopy.titlePlaceholder),
                    axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1...3)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .id(titleGeneration)
                    .accessibilityLabel(InboxCopy.titleLabel)
            }
            .id(CardField.title)
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
                    label: Copy.deferLabel,
                    value: $session.draft.deferDate,
                    today: session.today)
                DateValueChip(
                    label: Copy.due,
                    value: $session.draft.due,
                    today: session.today)
                Chip(
                    projectChipTitle,
                    state: projectChipTitle == Copy.project ? .unset : .confirmed,
                    symbol: projectChipTitle == Copy.project ? "plus" : nil
                ) {
                    session.sheet = .project
                }
            }
        }
    }

    /// Unset: the `plus` symbol is the "+", so the title is the bare label (no `+ + Project`) —
    /// same wording and casing as `DateValueChip` next to it and as the action detail.
    private var projectChipTitle: String {
        session.projectChipTitle(in: session.snapshot) ?? Copy.project
    }

    // MARK: Drag feedback (STYLEGUIDE §3.6)

    private var dragAlignment: Alignment {
        switch dragTarget {
        case .next: return .trailing
        case .someday: return .leading
        case .collapse: return .bottom
        default: return .center
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

    /// STYLEGUIDE §3.6's tint column: `accentWash` for Next, `fillQuiet` for Someday, **none**
    /// for the downward drag, which only collapses the card.
    private func tint(for exit: InboxExit) -> Color {
        switch exit {
        case .next: Color.accentWash
        case .collapse: Color.clear
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
