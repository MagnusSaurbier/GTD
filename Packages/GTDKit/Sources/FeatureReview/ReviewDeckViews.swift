#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Step 2 (§10.2): a card deck with three phases. The card itself is read-only `ItemCard`
/// content (STYLEGUIDE §3.10) — this step is about the commitment tier, not about editing.
/// Keys: `K` keep · `D` demote · `P` promote · `T` trash, with the legend row under the card.
struct ReviewDeckStep: View {
    @Bindable var session: ReviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: session.deckPhase?.title ?? Copy.weeklyReview,
                counter: session.deckCounter,
                symbol: ReviewSymbols.projects)

            capLine

            if let card = session.currentDeckCard {
                deckCard(card)
                choices(for: card)
                KeyLegendRow(card.choices.map {
                    KeyLegendRow.Entry(key: $0.key, label: $0.title)
                })
            } else {
                ContentUnavailableView(
                    ReviewCopy.deckDoneTitle,
                    systemImage: ReviewSymbols.done,
                    description: Text(ReviewCopy.deckDoneBody))
            }
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
                .keyboardShortcut(Self.shortcut(for: choice), modifiers: [])
                .accessibilityLabel(choice.title)
            }
        }
    }

    /// STYLEGUIDE §3.10 keys, spelled out rather than derived from `DeckChoice.key` at runtime,
    /// so a one-character assumption can never trap.
    private static func shortcut(for choice: DeckChoice) -> KeyEquivalent {
        switch choice {
        case .keep: "k"
        case .demote: "d"
        case .promote, .activate: "p"
        case .trash, .drop: "t"
        }
    }
}
#endif
