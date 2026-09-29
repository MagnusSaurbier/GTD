#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Which field of the card has the keyboard. While one of them is focused, swipes and the
/// letter/arrow keys are off (STYLEGUIDE §3.6).
enum CardField: Hashable {
    /// The title — for an inbox card, the file name (C3).
    case text
    /// The inbox note's body, shown only when it has something in it.
    case body
    case why
    case what
    case notes
    /// Scroll anchors only — never focused: the chip rows the keyboard cursor walks (#65), so a
    /// long card scrolls the highlighted row into view the way it does a focused field.
    case contextChips
    case timeChips

    /// The anchor of the row the keyboard cursor stands on. The outcome row sits under the card,
    /// outside the scroll view, so it needs none.
    static func anchor(for cursor: CardKeyCursor?) -> CardField? {
        switch cursor?.row {
        case .context: .contextChips
        case .time: .timeChips
        case .outcome, nil: nil
        }
    }
}

/// The inbox card (STYLEGUIDE §3.5): same view in both steps, expanding **in place**. Step 1 is
/// the meta line plus the editable title (the file name, C3) and — when the note has one — its
/// body, and nothing else; step 2a adds `Why?`,
/// `What?` and the chips; step 2b adds the `Notes` field. The card never truncates the capture
/// text — beyond the available height it scrolls **inside the card** (the only place a card
/// scrolls internally); there is no `Show all` any more (§3.5).
struct InboxCardView: View {
    @Bindable var session: InboxSession
    @FocusState.Binding var focus: CardField?
    /// Non-nil while a drag is past its threshold — drives the destination label and the tint.
    let dragTarget: InboxExit?
    let translation: CGSize
    let shake: CGFloat
    /// `⌘↩` past the last text field (`What?`): the host hands the keyboard to the card and
    /// starts the chip walk (#65).
    var onLeaveFields: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.listIcons) private var listIcons
    /// Caps how tall the raw-text field may grow before it scrolls internally (§3.5). Scales with
    /// Dynamic Type rather than a fixed pixel count (STYLEGUIDE §2.3).
    @ScaledMetric(relativeTo: .title3) private var rawTextMaxHeight: CGFloat = 260

    private var rotation: Double {
        guard !reduceMotion else { return 0 }
        let fraction = max(min(translation.width / 400, 1), -1)
        return fraction * DragThresholds.maxRotationDegrees
    }

    var body: some View {
        ItemCard {
            metaLine
            rawText
            switch session.step {
            case .step1:
                EmptyView()
            case .actionCard:
                actionFields
            case .keepCard:
                notesSection
            }
        }
        // Forces a fresh `TextField` per card: a programmatic draft reset when the head of the
        // queue advances (`InboxSession.syncDraft()`) does not reliably reach an unfocused
        // multi-line `TextField` bound two-way without an identity change — seen live on device
        // (the raw-text field kept the filed card's text one card into the next). The meta line,
        // which reads `session.current` directly rather than through a bound field, always had
        // the right card; only the bound text lagged.
        .id(session.current?.id)
        .animation(reduceMotion ? Motion.reduced : Motion.standard, value: session.step)
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

    // MARK: 2. Title (the file name) and body

    /// C3/R-4 — the note's title **is** its file name: this field shows `Inbox/<title>.md`'s
    /// name, and a changed title renames the file before the card is filed
    /// (`InboxSession.persistEdits`). Step 2a's "title still editable on tap" is this same field.
    /// The body follows it, secondary, only when the note has one worth reading — a long capture
    /// keeps its full text there, an Obsidian-made note its own lines; the empty Why/What
    /// template skeleton is not shown (`InboxSession.showsBody`).
    ///
    /// Only the **step-1 small card** scrolls internally past `rawTextMaxHeight` (STYLEGUIDE
    /// §3.5: "the only place a card scrolls internally"); a `ScrollView` always claims up to its
    /// `maxHeight`, even for one line of text, so wrapping an *opened* card's title in one too
    /// left a fixed-looking gap between it and `Notes`/`Why?` (T15 defect 5) — 2a and 2b hug their
    /// content and scroll with the page instead (§3.5 "an opened card … scrolls with the page").
    @ViewBuilder private var rawText: some View {
        let title = TextField(
            "",
            text: $session.draft.title,
            prompt: Self.prompt(InboxCopy.rawTextPlaceholder),
            axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typo.cardText)
            .foregroundStyle(Color.ink)
            // Never compressed: without this the last line loses its descenders.
            .fixedSize(horizontal: false, vertical: true)
            .focused($focus, equals: .text)
            .accessibilityLabel(InboxCopy.rawTextPlaceholder)

        let field = VStack(alignment: .leading, spacing: Spacing.s) {
            title
            if session.showsBody {
                NoteEditor(text: $session.draft.body, tone: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focus, equals: .body)
                    .accessibilityLabel(InboxCopy.bodyLabel)
            }
        }

        if session.step == .step1 {
            ScrollView {
                field
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: rawTextMaxHeight)
            .id(CardField.text)
        } else {
            field.id(CardField.text)
        }
    }

    // MARK: Step 2a — Why? / What? / chips

    @ViewBuilder private var actionFields: some View {
        field(
            label: Copy.why,
            isMissing: session.isMissing(.why),
            placeholder: Copy.whyPlaceholder,
            text: $session.draft.why,
            field: .why)
        whatSection
        chips
    }

    private func field(
        label: String,
        isMissing: Bool,
        placeholder: String,
        text: Binding<String>,
        field: CardField
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(label, isMissing: isMissing)
            NoteEditor(text: text, prompt: placeholder)
                .onAdvance { advance(from: field) }
                .onRetreat { focus = Self.previous(before: field, showsBody: session.showsBody) }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
        }
        .id(field)
    }

    /// `⌘↩` past a field's last input line (STYLEGUIDE §4.4): `Why?` → `What?`; after `What?`
    /// (and every other body field) the keyboard goes back to the card, so the keys act on it.
    static func next(after field: CardField) -> CardField? {
        field == .why ? .what : nil
    }

    /// `⇧⌘↩` above a field's first input line: `What?` → `Why?` → the note's body when the card
    /// shows one, else the title. Every other field keeps the focus where it is (`nil` would
    /// give the keys back to the card, which is not "previous").
    static func previous(before field: CardField, showsBody: Bool) -> CardField? {
        switch field {
        case .what: .why
        case .why: showsBody ? .body : .text
        case .text, .body, .notes, .contextChips, .timeChips: field
        }
    }

    /// After `What?` the host takes over: the keyboard leaves the fields for the chip walk.
    private func advance(from field: CardField) {
        if let next = Self.next(after: field) {
            focus = next
        } else {
            onLeaveFields()
        }
    }

    /// A placeholder must never read as an entered value (no lying defaults): it is tertiary,
    /// the value is `ink`. macOS otherwise draws the prompt of a plain field in the text colour.
    private static func prompt(_ placeholder: String) -> Text {
        Text(placeholder).foregroundStyle(Color.textTertiary)
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                SectionLabel(Copy.what, isMissing: session.isMissing(.what))
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
            NoteEditor(text: $session.draft.what, prompt: Copy.whatPlaceholder)
                .onAdvance { advance(from: .what) }
                .onRetreat { focus = Self.previous(before: .what, showsBody: session.showsBody) }
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

    // MARK: Step 2a — chips

    private var chips: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.contextGroupLabel, isMissing: session.isMissing(.context),
                    font: Typo.meta, foreground: .textSecondary)
                ContextChipGroup(
                    contexts: session.contexts, selection: $session.draft.contexts,
                    highlighted: session.keyHighlight(in: .context))
            }
            .id(CardField.contextChips)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.timeGroupLabel, isMissing: session.isMissing(.timeEstimate),
                    font: Typo.meta, foreground: .textSecondary)
                TimeBucketChipGroup(
                    selection: $session.draft.timeBucket,
                    highlighted: session.keyHighlight(in: .time))
            }
            .id(CardField.timeChips)
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
                    state: isProjectChosen ? .confirmed : .unset,
                    symbol: isProjectChosen ? nil : "plus"
                ) {
                    session.sheet = .project
                }
            }
        }
    }

    /// Unset: the `plus` symbol is the "+", so the title is the bare, lowercase label (no
    /// `+ + Project`, no `+ Project`) — same wording and casing as `DateValueChip` next to it
    /// (STYLEGUIDE §3.1/§3.5's `+ project`).
    private var chosenProjectTitle: String? { session.projectChipTitle(in: session.snapshot) }
    private var isProjectChosen: Bool { chosenProjectTitle != nil }
    private var projectChipTitle: String {
        chosenProjectTitle ?? Copy.unsetValueChipTitle(Copy.project)
    }

    // MARK: Step 2b — Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(InboxCopy.notesLabel)
            NoteEditor(text: $session.draft.notes, prompt: InboxCopy.notesPlaceholder)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: .notes)
                .accessibilityLabel(InboxCopy.notesLabel)
        }
        .id(CardField.notes)
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
            Label(dragTarget.title, systemImage: dragTarget.symbol(icons: listIcons))
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
                .padding(Spacing.l)
                .allowsHitTesting(false)
        }
    }

    /// STYLEGUIDE §3.6's tint column: `accentWash` for Next, `fillQuiet` for Someday, **none**
    /// for the downward drag, which only collapses the card. No swipe ever trashes, so there is
    /// no trash tint to compute here.
    private func tint(for exit: InboxExit) -> Color {
        switch exit {
        case .next: Color.accentWash
        case .collapse: Color.clear
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
