#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// The guided, resumable weekly review (§10, Mac). A stock window: the four-stage rail on the
/// left (STYLEGUIDE §3.10), the current step centred at 720 pt, and a `Back` / `Continue` bar
/// at the bottom. Every decision it makes lives in `ReviewSession`.
public struct WeeklyReviewView: View {
    private let onFinished: () -> Void
    private let store: any ReviewStateStore
    @Environment(AppModel.self) private var model
    @State private var session: ReviewSession?

    public init(onFinished: @escaping () -> Void) {
        self.init(store: FileReviewStateStore(), onFinished: onFinished)
    }

    /// Same view with an injected store — used by previews, tests and the app shell when the
    /// wizard state should not go to the default Application Support file.
    public init(store: any ReviewStateStore, onFinished: @escaping () -> Void) {
        self.store = store
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            Color.surfaceGrouped.ignoresSafeArea()
            if let session {
                ReviewWizardView(session: session, onFinished: onFinished)
            }
        }
        .task {
            if session == nil { session = ReviewSession(model: model, store: store) }
        }
    }
}

/// Shown by the shell while a review is in progress, so an interrupted review is never lost
/// behind a menu item (§10 "resumable").
public struct ReviewResumeBanner: View {
    private let onResume: () -> Void
    private let store: any ReviewStateStore

    public init(onResume: @escaping () -> Void) {
        self.init(store: FileReviewStateStore(), onResume: onResume)
    }

    public init(store: any ReviewStateStore, onResume: @escaping () -> Void) {
        self.store = store
        self.onResume = onResume
    }

    public var body: some View {
        if let state = ReviewSession.resumable(in: store) {
            HStack(spacing: Spacing.m) {
                Label(ReviewCopy.resumeBannerTitle, systemImage: ReviewSymbols.review)
                    .font(Typo.meta)
                    .foregroundStyle(Color.ink)
                Text(ReviewCopy.resumeBannerDetail(year: state.year, week: state.week))
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: Spacing.s)
                Button(ReviewCopy.resume, action: onResume)
            }
            .padding(Spacing.m)
            .background(Color.surfaceCard, in: Radius.tileShape)
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - The wizard frame (STYLEGUIDE §3.10)

struct ReviewWizardView: View {
    @Bindable var session: ReviewSession
    let onFinished: () -> Void

    @State private var isShowingStale = false
    /// The rail is a column of text, so its width follows the system text size (STYLEGUIDE §8:
    /// "Mac respects system text size"). At a fixed 220 pt the stage sub-steps clipped.
    @ScaledMetric(relativeTo: .headline) private var railWidth: CGFloat = 220

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            rail
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                ScrollView {
                    content
                        .frame(maxWidth: contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                        .padding(.horizontal, Spacing.screenMargin)
                }
                Divider()
                bottomBar
            }
        }
        .padding(Spacing.screenMargin)
        .onAppear { isShowingStale = session.staleState != nil }
        .sheet(isPresented: $isShowingStale) { staleSheet }
    }

    private var contentMaxWidth: CGFloat { 720 }

    private var rail: some View {
        ReviewWizardRail(
            stages: session.rail.map {
                ReviewWizardRail.Stage(
                    title: $0.title, subSteps: $0.subSteps, isComplete: $0.isComplete)
            },
            current: session.rail.first(where: \.isCurrent)?.title)
            .frame(width: railWidth, alignment: .leading)
            .accessibilityLabel(Copy.weeklyReview)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            // The window (or navigation bar) already carries the "Weekly review" title; the
            // header names only what the title cannot: which week this review is for.
            Text(ReviewCopy.weekLabel(year: session.state.year, week: session.state.week))
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.s)
            Button(ReviewCopy.quit, action: onFinished)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.bottom, Spacing.m)
    }

    @ViewBuilder private var content: some View {
        switch session.page {
        case .sweepInbox: SweepInboxStep(session: session)
        case .sweepDeferred: SweepDeferredStep(session: session)
        case .sweepWaiting: SweepWaitingStep(session: session)
        case .sweepStalled: SweepStalledStep(session: session)
        case .deckNext, .deckSomeday, .deckProjects: ReviewDeckStep(session: session)
        case .systemsCheck: SystemsCheckStep(session: session)
        case .reflection: ReflectionStep(session: session)
        case .summary: ReviewSummaryStep(session: session, onFinished: onFinished)
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if session.page != .summary {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let reason = session.blockReason {
                    Label(reason, systemImage: Symbols.aging)
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                }
                if let error = session.lastError {
                    Label(ReviewCopy.errorText(error), systemImage: Symbols.overdue)
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: Spacing.m) {
                    Button(ReviewCopy.back) { session.back() }
                        .disabled(!session.canGoBack)
                    Spacer()
                    if session.isLastPageBeforeSave {
                        Button(ReviewCopy.saveAndFinish) {
                            Task { await session.save() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(ReviewCopy.cont) { session.advance() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!session.canContinue)
                    }
                }
            }
            .padding(.top, Spacing.m)
        }
    }

    /// An unfinished review from an earlier week: discard or continue, never silently either.
    private var staleSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(ReviewCopy.staleTitle).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            if let stale = session.staleState {
                Text(ReviewCopy.staleBody(year: stale.year, week: stale.week))
                    .font(Typo.body)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: Spacing.m) {
                Button(ReviewCopy.staleDiscard) {
                    session.discardStale()
                    isShowingStale = false
                }
                Spacer()
                Button(ReviewCopy.staleContinue) {
                    session.continueStale()
                    isShowingStale = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(minWidth: 360)
    }
}

// MARK: - Shared step chrome

/// Title + optional counter above every step's content, so the steps themselves stay short.
struct ReviewStepHeader: View {
    let title: String
    var counter: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(title).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.s)
            if let counter {
                Text(counter).font(Typo.counter).foregroundStyle(Color.textSecondary)
            }
        }
    }
}

/// A borderless multi-line field with a label above it (STYLEGUIDE §4.4 — no Save buttons,
/// editing autosaves).
struct ReviewTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            if let footnote {
                Text(footnote).font(Typo.counter).foregroundStyle(Color.textSecondary)
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .lineLimit(2...6)
                .accessibilityLabel(label)
        }
    }
}
#endif
