#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Step 2 (§10.2): a card deck with three phases. The card itself is read-only `ItemCard`
/// content (STYLEGUIDE §3.10) — this step is about the commitment tier, not about editing.
/// Keys: `K` keep · `D` demote · `P` promote · `T` trash (rebindable, R-10), with the legend row
/// under the card rendered from `bindings` — never the fixed default (STYLEGUIDE §3.10/§4.5).
struct ReviewDeckStep: View {
    @Bindable var session: ReviewSession
    var bindings: KeyBindings = .defaults
    /// R-3 — "offers to open the action for editing". The shell wires this to real navigation;
    /// a caller that has none (previews, an unwired app shell) still gets a working `Keep`.
    var onEditAction: (NoteID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: session.deckPhase?.title ?? Copy.weeklyReview,
                counter: session.deckCounter,
                symbol: ReviewSymbols.projects)

            capLine
            if session.deckPhase == .someday { untouchedLine }

            if let card = session.currentDeckCard {
                deckCard(card)
                if let fields = session.missingFieldsIssue {
                    missingFieldsNotice(fields, card: card)
                } else {
                    choices(for: card)
                    KeyLegendRow(bindings.legend(
                        for: .reviewDeck,
                        titles: Dictionary(uniqueKeysWithValues: card.choices.map { ($0.keyCommand, $0.title) })
                    ).map { KeyLegendRow.Entry(key: $0.key, label: $0.label) })
                }
            } else {
                ContentUnavailableView(
                    ReviewCopy.deckDoneTitle,
                    systemImage: ReviewSymbols.done,
                    description: Text(ReviewCopy.deckDoneBody))
            }
        }
        .sheet(isPresented: Binding(
            get: { session.capChoice != nil }, set: { if !$0 { session.cancelCapChoice() } })
        ) {
            capSheet
        }
    }

    /// The live cap count (STYLEGUIDE §2.2): `15/15` as a badge once it matters, plain text
    /// before that — it is information, not an alarm, until Next is actually full.
    @ViewBuilder private var capLine: some View {
        HStack(spacing: Spacing.s) {
            Text(Copy.next).font(Typo.meta).foregroundStyle(Color.textSecondary)
            if let signal = session.capSignal {
                Badge(SignalPresentation.badge(for: signal, today: session.today))
            } else {
                Text("\(session.nextCount)/\(session.cap)")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Spacing.s)
        }
    }

    /// STYLEGUIDE §3.10 — the Someday header's staleness stat.
    private var untouchedLine: some View {
        Text(Copy.untouchedOver30Days(session.somedayUntouchedOver30DaysCount))
            .font(Typo.counter)
            .foregroundStyle(Color.textSecondary)
    }

    @ViewBuilder private func deckCard(_ card: DeckCard) -> some View {
        ItemCard {
            Text(card.title).font(Typo.cardText).foregroundStyle(Color.ink)
            if let action = card.action {
                if !metaLine(action).isEmpty {
                    Text(metaLine(action)).font(Typo.meta).foregroundStyle(Color.textSecondary)
                }
                let badges = SignalPresentation.badges(
                    for: Rules.signals(for: action, today: session.today), today: session.today)
                if !badges.isEmpty {
                    HStack(spacing: Spacing.s) {
                        ForEach(badges, id: \.self) { Badge($0) }
                    }
                }
                if !action.why.isEmpty {
                    Text(Copy.why).font(Typo.sectionHeader).foregroundStyle(Color.ink)
                    CollapsibleText(action.why)
                }
                if !action.what.isEmpty {
                    Text(Copy.what).font(Typo.sectionHeader).foregroundStyle(Color.ink)
                    CollapsibleText(action.what)
                }
            }
            if let project = card.project {
                Text(Copy.projectStatus(project.status))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                if !project.outcome.isEmpty {
                    CollapsibleText(project.outcome)
                }
                Text(ReviewCopy.deckCounter(
                    done: project.steps.count { $0.done }, total: project.steps.count))
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .itemCardPeek(hasNext: session.currentDeckCards.count > 1)
    }

    private func metaLine(_ action: Action) -> String {
        var parts: [String] = []
        if let project = action.project.flatMap({ session.snapshot.project($0)?.title }) {
            parts.append(project)
        }
        parts.append(Copy.status(action.status))
        parts.append(contentsOf: action.contexts)
        if let bucket = action.timeBucket { parts.append("\(Copy.timeBucket(bucket)) min") }
        return parts.joined(separator: " · ")
    }

    private func choices(for card: DeckCard) -> some View {
        HStack(spacing: Spacing.m) {
            ForEach(card.choices) { choice in
                Button {
                    Task { await session.apply(choice, to: card) }
                } label: {
                    Label(choice.title, systemImage: choice.symbol).font(Typo.chip)
                }
                .keyboardShortcut(Self.shortcut(for: choice, bindings: bindings), modifiers: [])
                .accessibilityLabel(choice.title)
            }
        }
    }

    /// R-3 — a promote refused for missing required fields (STYLEGUIDE §3.10): the fields are
    /// named inline on the card, never an alert, and the card is never silently skipped — it
    /// stays until the user explicitly opens it to edit or keeps it as is.
    @ViewBuilder private func missingFieldsNotice(_ fields: [RequiredField], card: DeckCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(Copy.missingFields(fields), systemImage: Symbols.requiredField)
                .font(Typo.meta)
                .foregroundStyle(Color.signalAttention)
            HStack(spacing: Spacing.m) {
                Button(ReviewCopy.editAction) {
                    session.dismissMissingFieldsForEditing()
                    onEditAction(card.id)
                }
                Button(ReviewCopy.keepDespiteMissingFields) {
                    session.keepDespiteMissingFields(card)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The forced choice of D14: demote one of the current Next items and the refused promote is
    /// retried automatically, or `Cancel` — never an automatic "send to Someday instead".
    private var capSheet: some View {
        NavigationStack {
            List(session.capCandidates) { action in
                HStack {
                    Text(action.title).font(Typo.body).foregroundStyle(Color.ink)
                    Spacer(minLength: Spacing.s)
                    Button(ReviewCopy.capSheetDemote) {
                        Task { await session.demoteAndRetryDeckCard(action.id) }
                    }
                }
            }
            .navigationTitle(Copy.capSheetTitle)
            .safeAreaInset(edge: .bottom) {
                Text(Copy.capSheetBody)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                    .padding(Spacing.m)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ReviewCopy.capSheetCancel) { session.cancelCapChoice() }
                }
            }
        }
    }

    /// STYLEGUIDE §3.10 keys, spelled out rather than derived from `DeckChoice.key` at runtime,
    /// so a one-character assumption can never trap. Rebindable (R-10): resolves through
    /// `bindings` instead of the fixed default.
    private static func shortcut(for choice: DeckChoice, bindings: KeyBindings) -> KeyEquivalent {
        let display = bindings.key(for: choice.keyCommand).display.lowercased()
        // `KeyStroke.display` is never empty by construction; the fallback only guards the type.
        return KeyEquivalent(display.first ?? Character(choice.key.lowercased()))
    }
}
#endif
