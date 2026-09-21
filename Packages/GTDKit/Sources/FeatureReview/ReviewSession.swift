import Foundation
import Observation
import GTDModel
import GTDAppCore
import GTDStats

/// The guided, resumable weekly review (§10) — everything about it that is not a pixel.
///
/// The wizard is a flat list of `ReviewPage`s over the four stages of §10; `state` is the whole
/// of what has to survive a relaunch, and it is written to the injected `ReviewStateStore` after
/// every mutation. Views hold no decisions: they render what this object exposes and call back
/// in. Plain and unit-testable — **no SwiftUI**.
///
/// Two gates live here rather than in a view, because they are the point of their step: the
/// sweep cannot be left with items still in the inbox (§10.1.1 "inbox to zero"), and the deck
/// cannot be left while Next is over its cap (§10.2 "Ends with Next ≤ 15").
@MainActor
@Observable
public final class ReviewSession {

    // MARK: - State

    public private(set) var state: ReviewSessionState

    /// A session from an **earlier** week that was never finished. It is never silently adopted
    /// and never silently dropped: the wizard offers `continueStale()` or `discardStale()`.
    public private(set) var staleState: ReviewSessionState?

    /// The last refused command, shown inline (STYLEGUIDE §4.3 — never an alert).
    public private(set) var lastError: GTDError?

    private let model: AppModel
    private let store: any ReviewStateStore
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        model: AppModel,
        store: any ReviewStateStore = FileReviewStateStore(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.model = model
        self.store = store
        self.now = now
        self.calendar = calendar

        let week = ISOWeek(containing: model.today())
        let saved = store.load()
        let fresh = ReviewSessionState(
            year: week.year,
            week: week.week,
            page: .sweepInbox,
            startedAt: now(),
            inboxAtStart: Rules.inboxQueue(model.snapshot).count)

        if let saved, !saved.isSaved, saved.isFor(year: week.year, week: week.week) {
            // Same week, unfinished — resume exactly where it stopped.
            state = saved
            staleState = nil
        } else if let saved, !saved.isSaved {
            // An earlier week's review was never finished. This week's starts fresh, but the old
            // one stays on offer instead of being thrown away silently.
            state = fresh
            staleState = saved
        } else {
            state = fresh
            staleState = nil
        }
        store.save(state)
    }

    /// The review in progress on this device, or `nil` — what the shell's `ReviewResumeBanner`
    /// keys off. An already-saved session does not count as in progress.
    public static func resumable(in store: any ReviewStateStore) -> ReviewSessionState? {
        guard let state = store.load(), !state.isSaved else { return nil }
        return state
    }

    /// Pick up the unfinished review from the earlier week, its week number and all.
    public func continueStale() {
        guard let staleState else { return }
        self.staleState = nil
        write(staleState)
    }

    /// Throw the earlier week's progress away and keep this week's fresh session.
    public func discardStale() {
        staleState = nil
    }

    public func clearError() { lastError = nil }

    /// The one place `state` changes, so persistence can never be forgotten at a call site.
    private func mutate(_ body: (inout ReviewSessionState) -> Void) {
        var updated = state
        body(&updated)
        write(updated)
    }

    private func write(_ updated: ReviewSessionState) {
        state = updated
        store.save(updated)
    }

    // MARK: - Snapshot access

    public var snapshot: VaultSnapshot { model.snapshot }
    public var today: Day { model.today() }
    public var week: ISOWeek { ISOWeek(year: state.year, week: state.week) }

    /// The day the seven-day windows end on: the **last day of the week under review**.
    ///
    /// `WeeklyStats.compute` anchors on exactly that day internally, so handing the same day to
    /// `RoutineAudit.compute` is what keeps the stat tiles and the heatmap describing one and
    /// the same week — even when the review is actually done on the following Tuesday.
    public var reviewDay: Day { week.days.last ?? today }

    // MARK: - Navigation

    public var page: ReviewPage { state.page }
    public var rail: [ReviewRailItem] { ReviewRailItem.rail(for: state.page) }
    public var canGoBack: Bool { state.page.previous != nil }

    /// Why `Continue` is disabled, or `nil` when it is not. The wizard shows the reason rather
    /// than a dead button (STYLEGUIDE §1 "no lying UI").
    public var blockReason: String? {
        switch state.page {
        case .sweepInbox:
            let remaining = inboxRemaining
            return remaining == 0 ? nil : ReviewCopy.inboxNotEmpty(remaining)
        case .deckProjects:
            guard isOverCap else { return nil }
            return ReviewCopy.overCap(count: nextCount, cap: cap)
        default:
            return nil
        }
    }

    public var canContinue: Bool { blockReason == nil && state.page != .summary }

    /// `Save and finish` replaces `Continue` on the last page before the note is written.
    public var isLastPageBeforeSave: Bool { state.page == ReviewPage.lastBeforeSave }

    public func advance() {
        guard canContinue, let next = state.page.next, next != .summary else { return }
        lastError = nil
        mutate { $0.page = next }
    }

    public func back() {
        guard let previous = state.page.previous else { return }
        lastError = nil
        mutate { $0.page = previous }
    }

    /// Jump to a stage from the rail. Backwards only — including back to the first sub-step of
    /// the stage the wizard is already in. Forward jumps would walk straight past the gates.
    public func go(to stage: ReviewStage) {
        guard state.page.stage != nil, stage.firstPage.index < state.page.index else { return }
        lastError = nil
        mutate { $0.page = stage.firstPage }
    }

    // MARK: - The cap

    public var cap: Int { model.snapshot.config.nextCap }
    public var nextCount: Int { Rules.countsTowardCap(model.snapshot, today: today) }
    public var isOverCap: Bool { nextCount > cap }
    /// `15/15` or `17/15` — the live cap count the deck step shows (STYLEGUIDE §2.2).
    public var capSignal: Signal? { Rules.capSignal(model.snapshot, today: today) }

    // MARK: - Sweep: inbox (§10.1.1)

    public var inboxRemaining: Int { Rules.inboxQueue(model.snapshot).count }
    public var isInboxZero: Bool { inboxRemaining == 0 }
    /// How many items this review took out of the inbox.
    public var inboxProcessed: Int { max(0, state.inboxAtStart - inboxRemaining) }

    // MARK: - Sweep: items deferred to review (§10.1.2, I5)

    /// Deferred items that still need a decision, oldest first, each carrying its reason.
    public var deferredItems: [InboxItem] {
        let handled = Set(state.handledDeferred)
        return Rules.reviewDeferredInbox(model.snapshot).filter { !handled.contains($0.id.path) }
    }

    public var currentDeferredItem: InboxItem? { deferredItems.first }

    /// Files one deferred item and records the system fix it taught us (I5). The fix note is
    /// optional — an item that merely needed a decision is not a system failure, and an empty
    /// field must not write an empty line into the review note.
    public func fileDeferred(_ item: InboxItem, decision: InboxDecision, systemFix: String) async {
        guard await send(.fileInbox(item.id, decision)) else { return }
        let fix = systemFix.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { state in
            if !fix.isEmpty {
                state.systemFixNotes.append(ReviewCopy.systemFixNote(
                    item: item.text, reason: item.reviewReason ?? "", fix: fix))
            }
            state.handledDeferred.append(item.id.path)
            state.changes.deferredHandled += 1
        }
    }

    // MARK: - Sweep: waiting (§10.1.3)

    public var waitingItems: [Action] {
        let handled = Set(state.handledWaiting)
        return Rules.waitingList(model.snapshot, today: today).filter { !handled.contains($0.id.path) }
    }

    /// How long this item has been waiting, for the row's meta line (W2).
    public func waitingSince(_ action: Action) -> Int? {
        Rules.waitingSince(action, today: today, calendar: calendar)
    }

    /// The dashed suggestion offered with a chase or a bump — never written until confirmed.
    public func suggestedFollowUp(for choice: WaitingSweep.Choice) -> Day? {
        WaitingSweep.suggestedFollowUp(for: choice, today: today)
    }

    public func apply(_ choice: WaitingSweep.Choice, to action: Action, followUp: Day? = nil) async {
        guard let command = WaitingSweep.command(choice, action: action, followUp: followUp),
              await send(command)
        else { return }
        mutate { state in
            state.handledWaiting.append(action.id.path)
            state.changes.waitingHandled += 1
        }
    }

    // MARK: - Sweep: stalled projects (§10.1.4, P4)

    public var stalledProjects: [Project] {
        let handled = Set(state.handledStalled)
        return Rules.stalledProjects(model.snapshot, today: today)
            .filter { !handled.contains($0.id.path) }
    }

    public func apply(_ choice: StalledSweep.Choice, to project: Project) async {
        if let command = StalledSweep.command(choice, project: project) {
            guard await send(command) else { return }
            mutate { $0.changes.projectsTouched += 1 }
        }
        markStalledHandled(project)
    }

    /// Takes a project off the sweep list without issuing a second command — `WhatsNextSheet`
    /// (`addNextAction`) already did the work with its own `promoteStep`.
    ///
    /// It **verifies** rather than trusts (T41). The sheet can be closed without promoting
    /// anything — the cap can refuse the promotion, or the user can just press Done — and
    /// marking the project handled anyway would drop a still-stalled project silently out of
    /// §10.1.4, which is the one step whose whole job is to find them. A project that is still
    /// stalled stays on the list.
    public func markStalledHandled(_ project: Project) {
        if let current = model.snapshot.project(project.id),
           Rules.isStalled(current, in: model.snapshot, today: today) {
            return
        }
        guard !state.handledStalled.contains(project.id.path) else { return }
        mutate { $0.handledStalled.append(project.id.path) }
    }

    // MARK: - Deck (§10.2)

    public var deckPhase: DeckPhase? { state.page.deckPhase }

    /// The cards of `phase` that still need a decision.
    public func deckCards(for phase: DeckPhase) -> [DeckCard] {
        let handled = Set(state.handledDeckCards)
        return ReviewDeck.cards(for: phase, in: model.snapshot, today: today)
            .filter { !handled.contains($0.id.path) }
    }

    public var currentDeckCards: [DeckCard] {
        guard let phase = deckPhase else { return [] }
        return deckCards(for: phase)
    }

    public var currentDeckCard: DeckCard? { currentDeckCards.first }

    /// `4 of 17` — how far through this phase the user is, or `nil` when the phase is empty.
    public var deckCounter: String? {
        guard let phase = deckPhase else { return nil }
        let all = ReviewDeck.cards(for: phase, in: model.snapshot, today: today)
        guard !all.isEmpty else { return nil }
        let handled = Set(state.handledDeckCards)
        return ReviewCopy.deckCounter(
            done: all.count { handled.contains($0.id.path) }, total: all.count)
    }

    /// Applies a deck choice. A refused command (the cap, most likely) leaves the card on the
    /// deck so the user can choose again — never a silent skip.
    public func apply(_ choice: DeckChoice, to card: DeckCard) async {
        guard card.choices.contains(choice) else { return }
        if let command = ReviewDeck.command(for: choice, card: card) {
            guard await send(command) else { return }
        }
        mutate { state in
            state.handledDeckCards.append(card.id.path)
            state.changes.record(choice)
        }
    }

    /// Mac keys of STYLEGUIDE §3.10: `K` keep · `D` demote · `P` promote · `T` trash.
    public func choice(forKey key: String, on card: DeckCard) -> DeckChoice? {
        card.choices.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }
    }

    // MARK: - Systems check (§10.3)

    /// Bound by the three free-text fields. Every keystroke persists, so an interrupted review
    /// loses at most the character being typed.
    public var systemsCheck: SystemsCheckAnswers {
        get { state.systemsCheck }
        set { mutate { $0.systemsCheck = newValue } }
    }

    public var stats: WeeklyStats {
        WeeklyStats.compute(snapshot: model.snapshot, week: week, calendar: calendar)
    }

    public var previousStats: WeeklyStats {
        WeeklyStats.compute(snapshot: model.snapshot, week: week.previous, calendar: calendar)
    }

    public var statTiles: [ReviewStatTile] { ReviewStats.tiles(stats, previous: previousStats) }

    /// The routine audit heatmaps (§10.3), over the same seven days as `stats`.
    public var heatmaps: [ReviewHeatmap] {
        ReviewStats.heatmaps(RoutineAudit.compute(
            routines: model.snapshot.routines,
            log: model.snapshot.routineLog,
            endingOn: reviewDay))
    }

    // MARK: - Reflection (§10.4)

    public var answers: WeeklyReviewAnswers {
        get { state.review }
        set { mutate { $0.review = newValue } }
    }

    public var lastReview: WeeklyReview? { model.snapshot.lastReview }

    /// Last week's `goal for next week`, shown beside "What did I want to achieve?" (§10.4).
    /// `nil` rather than an empty box when there is no earlier review.
    public var lastWeeksGoal: String? {
        guard let goal = lastReview?.goalForNextWeek.trimmingCharacters(in: .whitespacesAndNewlines),
              !goal.isEmpty
        else { return nil }
        return goal
    }

    public var noteID: NoteID {
        model.snapshot.config.layout.reviewPath(year: state.year, week: state.week)
    }

    /// The note this review will write, from the state as it stands. Re-saving the same week
    /// carries the existing note's unknown frontmatter and body sections through (N2).
    public func buildReview() -> WeeklyReview {
        let answers = state.review
        let existing = model.snapshot.lastReview
        let sameNote = existing?.year == state.year && existing?.week == state.week
        return WeeklyReview(
            year: state.year,
            week: state.week,
            wantedToAchieve: answers.wantedToAchieve,
            achieved: answers.achieved,
            behaviorToChange: answers.behaviorToChange,
            whatToStop: answers.whatToStop,
            howIGrew: answers.howIGrew,
            howToGrowFurther: answers.howToGrowFurther,
            whatToTry: answers.whatToTry,
            goalForNextWeek: answers.goalForNextWeek,
            systemFixNotes: state.systemFixNotes + state.systemsCheck.notes,
            passthrough: sameNote ? (existing?.passthrough ?? .empty) : .empty)
    }

    /// Writes `GTD/Reviews/<yyyy>/KW <ww>.md` (§10.4) and moves to the summary. The stored
    /// session is cleared: a finished review is not something to resume into.
    @discardableResult
    public func save() async -> Bool {
        guard await send(.saveWeeklyReview(buildReview())) else { return false }
        var updated = state
        updated.isSaved = true
        updated.page = .summary
        state = updated
        store.clear()
        return true
    }

    // MARK: - Summary (§10 "what changed this review")

    public struct SummaryRow: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        public var value: Int

        public init(id: String, label: String, value: Int) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    public var summaryRows: [SummaryRow] {
        let c = state.changes
        return [
            SummaryRow(id: "processed", label: ReviewCopy.summaryProcessed, value: inboxProcessed),
            SummaryRow(id: "deferred", label: ReviewCopy.summaryDeferred, value: c.deferredHandled),
            SummaryRow(id: "waiting", label: ReviewCopy.summaryWaiting, value: c.waitingHandled),
            SummaryRow(id: "demoted", label: ReviewCopy.summaryDemoted, value: c.demoted),
            SummaryRow(id: "promoted", label: ReviewCopy.summaryPromoted, value: c.promoted),
            SummaryRow(id: "trashed", label: ReviewCopy.summaryTrashed, value: c.trashed),
            SummaryRow(id: "projects", label: ReviewCopy.summaryProjects, value: c.projectsTouched),
        ]
    }

    /// The reward moment's `9 of 11 steps` line (STYLEGUIDE §5.2). The review's "steps" are its
    /// wizard pages; reaching the summary means every one of them was walked.
    public var walkedPages: Int { ReviewPage.allCases.count - 1 }
    public var totalPages: Int { ReviewPage.allCases.count - 1 }

    // MARK: - Sending

    /// The one place a command meets the backend, so a refusal always lands in `lastError`
    /// instead of being swallowed by a view.
    @discardableResult
    private func send(_ command: GTDCommand) async -> Bool {
        do {
            try await model.send(command)
            lastError = nil
            return true
        } catch let error as GTDError {
            lastError = error
            return false
        } catch {
            lastError = .invalid(String(describing: error))
            return false
        }
    }
}
