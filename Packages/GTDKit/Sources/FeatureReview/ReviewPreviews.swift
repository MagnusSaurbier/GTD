#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import GTDFixtures
import DesignSystem

// Previews for every wizard step, backed by `GTDFixtures.sampleSnapshot` (ARCHITECTURE §5).
// Each one uses an `InMemoryReviewStateStore` seeded on the page it wants to show, so no
// preview ever touches the real Application Support file.

@MainActor
enum ReviewPreview {
    static func model(_ snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        AppModel(
            backend: InMemoryBackend(snapshot: snapshot),
            snapshot: snapshot,
            today: { Fixtures.today })
    }

    static func store(_ page: ReviewPage) -> InMemoryReviewStateStore {
        let week = Fixtures.today.isoWeek
        return InMemoryReviewStateStore(ReviewSessionState(
            year: week.year,
            week: week.week,
            page: page,
            startedAt: Fixtures.date(Fixtures.today, 9, 0)))
    }

    static func session(_ page: ReviewPage, snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> ReviewSession {
        ReviewSession(
            model: model(snapshot),
            store: store(page),
            now: { Fixtures.date(Fixtures.today, 9, 0) },
            calendar: Fixtures.calendar)
    }

    /// A snapshot whose inbox is already empty, so the sweep's first gate is open.
    static var inboxZeroSnapshot: VaultSnapshot {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.inbox = snapshot.inbox.filter { $0.reviewReason != nil }
        return snapshot
    }
}

#Preview("Sweep · inbox") {
    ReviewWizardView(session: ReviewPreview.session(.sweepInbox), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Sweep · deferred") {
    ReviewWizardView(
        session: ReviewPreview.session(.sweepDeferred, snapshot: ReviewPreview.inboxZeroSnapshot),
        onFinished: {})
        .environment(ReviewPreview.model(ReviewPreview.inboxZeroSnapshot))
}

#Preview("Sweep · waiting") {
    ReviewWizardView(session: ReviewPreview.session(.sweepWaiting), onFinished: {})
        .environment(ReviewPreview.model())
        .preferredColorScheme(.dark)
}

#Preview("Sweep · stalled") {
    ReviewWizardView(session: ReviewPreview.session(.sweepStalled), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Deck · Next") {
    ReviewWizardView(session: ReviewPreview.session(.deckNext), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Deck · Someday") {
    ReviewWizardView(session: ReviewPreview.session(.deckSomeday), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Deck · Someday · AX1") {
    ReviewWizardView(session: ReviewPreview.session(.deckSomeday), onFinished: {})
        .environment(ReviewPreview.model())
        .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Deck · Someday · dark") {
    ReviewWizardView(session: ReviewPreview.session(.deckSomeday), onFinished: {})
        .environment(ReviewPreview.model())
        .preferredColorScheme(.dark)
}

#Preview("Deck · projects") {
    ReviewWizardView(session: ReviewPreview.session(.deckProjects), onFinished: {})
        .environment(ReviewPreview.model())
}

/// R-3 — a promote refused for missing required fields: the fields named inline, `Edit`/`Keep`.
#Preview("Deck · missing fields") {
    ReviewDeckMissingFieldsPreview()
}

/// A3/D14 — the cap's forced choice, triggered by promoting into a Next already at 15/15.
#Preview("Deck · cap sheet") {
    ReviewDeckCapSheetPreview()
}

#Preview("Systems check") {
    ReviewWizardView(session: ReviewPreview.session(.systemsCheck), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Systems check · AX1") {
    ReviewWizardView(session: ReviewPreview.session(.systemsCheck), onFinished: {})
        .environment(ReviewPreview.model())
        .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Reflection") {
    ReviewWizardView(session: ReviewPreview.session(.reflection), onFinished: {})
        .environment(ReviewPreview.model())
}

#Preview("Summary") {
    ReviewWizardView(session: ReviewPreview.session(.summary), onFinished: {})
        .environment(ReviewPreview.model())
        .preferredColorScheme(.dark)
}

/// Drives `ReviewSession.apply` once before showing the deck, so previews can show a state that
/// only exists after an interaction (R-3 missing fields, A3/D14 the cap) without any decision
/// logic living in the view itself — the session still does the deciding.
@MainActor
private struct ReviewDeckMissingFieldsPreview: View {
    @State private var session = ReviewPreview.session(.deckSomeday, snapshot: ReviewPreview.inboxZeroSnapshot)
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                ReviewWizardView(session: session, onFinished: {})
            } else {
                ProgressView()
            }
        }
        .environment(ReviewPreview.model(ReviewPreview.inboxZeroSnapshot))
        .task {
            guard !isReady else { return }
            if let card = session.deckCards(for: .someday).first(where: { card in
                guard let action = card.action else { return false }
                return action.why.isEmpty || action.contexts.isEmpty || action.timeEstimate == nil
            }) {
                await session.apply(.promote, to: card)
            }
            isReady = true
        }
    }
}

@MainActor
private struct ReviewDeckCapSheetPreview: View {
    @State private var session = ReviewPreview.session(.deckSomeday, snapshot: ReviewPreview.inboxZeroSnapshot)
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                ReviewWizardView(session: session, onFinished: {})
            } else {
                ProgressView()
            }
        }
        .environment(ReviewPreview.model(ReviewPreview.inboxZeroSnapshot))
        .task {
            guard !isReady else { return }
            func isComplete(_ card: DeckCard) -> Bool {
                guard let action = card.action else { return false }
                return !action.why.isEmpty && !action.what.isEmpty
                    && !action.contexts.isEmpty && action.timeEstimate != nil
            }
            while session.nextCount < session.cap,
                  let card = session.deckCards(for: .someday).first(where: isComplete) {
                await session.apply(.promote, to: card)
            }
            if let card = session.deckCards(for: .someday).first(where: isComplete) {
                await session.apply(.promote, to: card)
            }
            isReady = true
        }
    }
}

#Preview("Resume banner") {
    ReviewResumeBanner(store: ReviewPreview.store(.deckNext), onResume: {})
        .padding()
        .environment(ReviewPreview.model())
}
#endif
