import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// One inbox-processing session: LIFO queue, one card at a time, no skipping, exit only by
/// quitting (I1). Plain and unit-testable — **no SwiftUI**. Owned by T20.
///
/// Everything the card can do goes through this object: the five sub-flows, the cap choice, the
/// validation rule and undo. Views hold no decision logic; they render `draft`, `sheet` and
/// `queue` and call back in.
@MainActor
@Observable
public final class InboxSession {

    // MARK: - Draft

    /// What the user has decided about the card in front of them. Nothing here is written to the
    /// vault until the card is filed, and nothing is pre-filled (§1 "no lying defaults").
    public struct Draft: Sendable, Equatable {
        /// The raw captured text, editable in place (I2).
        public var text: String
        public var why: String
        public var what: String
        /// Only meaningful once `titleWasEdited` is true — otherwise the title is derived.
        public var title: String
        public var titleWasEdited: Bool
        public var contexts: [String]
        public var timeBucket: TimeBucket?
        public var deferDate: Day?
        public var due: Day?
        public var project: NoteID?

        public init(
            text: String = "",
            why: String = "",
            what: String = "",
            title: String = "",
            titleWasEdited: Bool = false,
            contexts: [String] = [],
            timeBucket: TimeBucket? = nil,
            deferDate: Day? = nil,
            due: Day? = nil,
            project: NoteID? = nil
        ) {
            self.text = text
            self.why = why
            self.what = what
            self.title = title
            self.titleWasEdited = titleWasEdited
            self.contexts = contexts
            self.timeBucket = timeBucket
            self.deferDate = deferDate
            self.due = due
            self.project = project
        }

        public init(item: InboxItem) {
            self.init(text: item.text)
        }

        /// The action note's title: first line of *What?*, falling back to the captured text,
        /// unless the user typed one (T20 brief: "editable before filing").
        public var effectiveTitle: String {
            if titleWasEdited {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return Draft.derivedTitle(what: what, text: text)
        }

        public static func derivedTitle(what: String, text: String) -> String {
            let fromWhat = ChecklistText.firstContentLine(what)
            let candidate = fromWhat.isEmpty ? ChecklistText.firstContentLine(text) : fromWhat
            return String(candidate.prefix(titleLimit))
        }

        /// A2 — a second checkbox in *What?* offers "Turn into project".
        public var suggestsProject: Bool { Checkbox.scan(what).count >= 2 }

        /// True while the user has changed nothing about this card.
        public func isPristine(for item: InboxItem) -> Bool {
            self == Draft(item: item)
        }

        static let titleLimit = 120
    }

    /// The five sub-flows and the cap choice, as the sheet the card is showing (I4).
    public enum Sheet: String, Sendable, Equatable, Identifiable, CaseIterable {
        case knowledge
        case project
        case waiting
        case deferToReview
        /// `Next is full` — demote one, or send this card to Someday. Never automatic.
        case cap
        /// The raw captured text in full, when the card had to collapse it (STYLEGUIDE §3.5).
        case fullText

        public var id: String { rawValue }
    }

    /// Why the card refused to leave. The card shakes and focuses the field — never an alert
    /// (STYLEGUIDE §3.6, §4.3). `nonce` changes on every refusal so a repeated one animates again.
    public struct Validation: Sendable, Equatable {
        public enum Issue: Sendable, Equatable {
            /// Next and Someday need a non-empty *What?*.
            case whatRequired
            /// Defer to review needs a reason (I5).
            case reasonRequired
        }

        public var issue: Issue
        public var nonce: Int
    }

    // MARK: - State

    public private(set) var queue: [InboxItem]
    /// The card being worked on, or `nil` when the session is finished (inbox zero).
    public var current: InboxItem? { queue.first }
    /// The current card's draft. Views bind straight to it.
    public var draft: Draft
    public var sheet: Sheet?
    public private(set) var processed: Int
    public private(set) var validation: Validation?
    /// The Next items offered for demotion while the cap sheet is up (I4, A3).
    public private(set) var capCandidates: [Action]
    /// An error that is neither the cap nor a validation issue (a title collision, say).
    public private(set) var lastError: GTDError?
    /// The one-time direction hint of STYLEGUIDE §3.6. **Stored**, so that dismissing it
    /// invalidates the view — the defaults flag behind it is not observable.
    public private(set) var isSwipeHintVisible: Bool

    private let model: AppModel
    private let defaults: any InboxDefaultsStore
    private let now: () -> Date
    private let startedAt: Date
    private var draftItemID: NoteID?
    private var counts: [CardTarget: Int] = [:]
    /// What the cap sheet would file once a slot is free.
    private var pending: (decision: InboxDecision, target: CardTarget)?
    /// One entry per filed card, so undo can put the card **and its draft** back (I6, N6).
    private var history: [(item: InboxItem, draft: Draft, target: CardTarget)] = []

    public init(
        model: AppModel,
        defaults: any InboxDefaultsStore = InboxDefaults.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = model
        self.defaults = defaults
        self.now = now
        self.startedAt = now()
        let items = Rules.inboxQueue(model.snapshot)
        self.queue = items
        self.processed = 0
        self.capCandidates = []
        self.isSwipeHintVisible = !defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint)
        self.draft = items.first.map(Draft.init(item:)) ?? Draft()
        self.draftItemID = items.first?.id
    }

    // MARK: - Derived

    /// `3 of 14 left` (STYLEGUIDE §6.3).
    public var counter: String {
        Copy.counter(remaining: queue.count, total: queue.count + processed)
    }

    /// Inbox zero: the queue is empty and the session can show its summary (§5 reward moment).
    public var isFinished: Bool { queue.isEmpty }

    public var canUndo: Bool { !history.isEmpty && model.undoLabel != nil }

    /// What `undo()` would revert, as the backend words it (N6).
    public var undoLabel: String? { model.undoLabel }

    /// The toast's wording, in the canonical form of STYLEGUIDE §6.3 (`Moved to Someday`).
    /// `nil` when there is nothing to undo.
    public var undoToastLabel: String? {
        guard canUndo, let last = history.last else { return nil }
        return last.target.undoToastLabel
    }

    public var snapshot: VaultSnapshot { model.snapshot }

    public var today: Day { model.today() }

    /// Contexts the chips offer, in config order (A4).
    public var contexts: [String] { model.snapshot.config.contexts }

    /// Signals for the current card — the inbox age badge (STYLEGUIDE §2.2, §3.5).
    public var currentSignals: [Signal] {
        guard let current else { return [] }
        return Rules.signals(for: current, today: today)
    }

    /// Per-target breakdown for the session summary, in card-target order.
    public var summaryCounts: [(target: CardTarget, count: Int)] {
        CardTarget.allCases.map { ($0, counts[$0] ?? 0) }
    }

    public var elapsedMinutes: Int {
        max(Int(now().timeIntervalSince(startedAt) / 60), 0)
    }

    /// Last knowledge folder used on this device — offered as a **suggestion**, never applied (I4).
    public var suggestedKnowledgeFolder: String? {
        defaults.string(forKey: InboxDefaultsKey.lastKnowledgeFolder)
    }

    /// Hides the one-time hint for good: the stored property invalidates the view, the flag
    /// keeps it away in the next session. A no-op once it is gone.
    public func dismissSwipeHint() {
        guard isSwipeHintVisible else { return }
        isSwipeHintVisible = false
        defaults.setFlag(true, forKey: InboxDefaultsKey.didShowSwipeHint)
    }

    public var knowledgeFolders: [String] { model.snapshot.knowledgeFolders }

    public var projectGroups: [ProjectGroup] { ProjectPicker.groups(model.snapshot) }

    // MARK: - Queue

    /// New captures that arrived mid-session go on top (LIFO, I7), and items that left the inbox
    /// elsewhere (another device, the weekly review) disappear from the queue.
    ///
    /// One refinement over a literal "always on top": a card the user is **already editing** is
    /// not yanked away — a fresh capture is then queued directly behind it and processed next.
    public func refresh() {
        let live = Rules.inboxQueue(model.snapshot)
        let liveByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        let known = Set(queue.map(\.id))
        let fresh = live.filter { !known.contains($0.id) }

        // Keep the order the session established, but pick up remote text edits.
        var kept = queue.compactMap { liveByID[$0.id] }

        if let head = kept.first, let current, head.id == current.id, !draft.isPristine(for: current) {
            kept.insert(contentsOf: fresh, at: 1)
            queue = kept
        } else {
            queue = fresh + kept
        }
        syncDraft()
    }

    // MARK: - Filing

    /// The single entry point for a swipe, a key and a VoiceOver action alike (STYLEGUIDE §3.6).
    public func choose(_ target: CardTarget) async {
        guard current != nil else { return }
        guard validate(for: target) else { return }
        switch target {
        case .next, .someday:
            guard let status = target.status else { return }
            await file(.action(actionDraft(status: status)), as: target)
        case .trash:
            await file(.trash, as: .trash)
        case .knowledge:
            sheet = .knowledge
        case .project:
            sheet = .project
        case .waiting:
            sheet = .waiting
        case .deferToReview:
            sheet = .deferToReview
        }
    }

    /// Validation before leaving: Next/Someday require a non-empty *What?* (STYLEGUIDE §3.6).
    /// Contexts and time may stay empty — undecided is a legal state.
    @discardableResult
    public func validate(for target: CardTarget) -> Bool {
        guard target.requiresWhat else { return true }
        guard draft.what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        fail(.whatRequired)
        return false
    }

    /// I4 — Knowledge: the capture file becomes the knowledge note. The folder is remembered on
    /// this device so the next card can *suggest* it.
    public func confirmKnowledge(folder: String, title: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        defaults.setString(folder, forKey: InboxDefaultsKey.lastKnowledgeFolder)
        await file(.knowledge(folder: folder, title: cleanTitle), as: .knowledge)
    }

    /// W1 — `WaitingInfo` exists only once the user confirmed both halves.
    public func confirmWaiting(_ info: WaitingInfo) async {
        await file(.action(actionDraft(status: .waiting, waiting: info)), as: .waiting)
    }

    /// I4 — Project: a new project (and optionally a new area) plus its first next action(s).
    public func confirmNewProject(_ projectDraft: ProjectDraft, firstActions: [ActionDraft]) async {
        await file(.newProject(projectDraft, firstActions: firstActions), as: .project)
    }

    public func confirmExistingProject(_ id: NoteID, actions: [ActionDraft]) async {
        await file(.existingProject(id, actions: actions), as: .project)
    }

    /// I5 — the escape hatch. The reason is required; the item leaves the queue and shows up in
    /// the weekly review with its reason.
    public func confirmDeferToReview(reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail(.reasonRequired)
            return
        }
        guard let item = current else { return }
        let filed = draft
        do {
            try await persistTextEdit(for: item)
            try await model.send(.deferInboxToReview(item.id, reason: trimmed))
            finish(item: item, draft: filed, target: .deferToReview)
        } catch let error as GTDError {
            lastError = error
        } catch {
            lastError = .invalid("\(error)")
        }
    }

    /// The first action(s) a project sub-flow offers, prefilled from the card but never persisted
    /// until the user confirms the sheet.
    public func firstActionDraft(for project: Project?) -> ActionDraft {
        var action = actionDraft(status: ProjectPicker.statusForFirstAction(in: project))
        action.project = project?.id
        return action
    }

    // MARK: - Cap (A3, I4)

    /// Demote one of the current Next items and file the card that was refused.
    public func demoteAndRetry(_ id: NoteID) async {
        guard let pending else { return }
        do {
            try await model.send(.setStatus(id, .someday, waiting: nil))
        } catch let error as GTDError {
            lastError = error
            return
        } catch {
            lastError = .invalid("\(error)")
            return
        }
        self.pending = nil
        sheet = nil
        await file(pending.decision, as: pending.target)
    }

    /// The other half of the forced choice: send this card to Someday instead (never automatic).
    public func sendToSomedayInstead() async {
        guard let pending else { return }
        self.pending = nil
        sheet = nil
        await file(Self.demoted(pending.decision), as: .someday)
    }

    /// Closes a sub-flow sheet without filing anything. The card and its draft stay.
    public func cancelSheet() {
        sheet = nil
        pending = nil
        capCandidates = []
    }

    public func clearError() { lastError = nil }

    // MARK: - Undo (I6, N6)

    /// Undo the last card: it comes back at the head of the queue **with its draft restored**.
    public func undo() async {
        guard let last = history.popLast() else { return }
        await model.undo()
        refresh()

        if let restored = model.snapshot.inboxItem(last.item.id), restored.reviewReason == nil {
            queue.removeAll { $0.id == restored.id }
            queue.insert(restored, at: 0)
            draft = last.draft
            draftItemID = restored.id
        } else {
            // The backend refused the undo — leave the session consistent with the vault.
            history.append(last)
            syncDraft()
            return
        }

        processed = max(processed - 1, 0)
        counts[last.target] = max((counts[last.target] ?? 1) - 1, 0)
        sheet = nil
        pending = nil
        capCandidates = []
    }

    // MARK: - Internals

    /// Builds the draft for a decision. Suggestions are never in here — only confirmed values.
    func actionDraft(status: ActionStatus, waiting: WaitingInfo? = nil) -> ActionDraft {
        ActionDraft(
            title: draft.effectiveTitle,
            status: status,
            contexts: draft.contexts,
            timeEstimate: draft.timeBucket?.minutes,
            project: draft.project,
            deferDate: draft.deferDate,
            due: draft.due,
            waiting: waiting,
            why: draft.why,
            what: draft.what)
    }

    private func file(_ decision: InboxDecision, as target: CardTarget) async {
        guard let item = current else { return }
        let filed = draft
        do {
            try await persistTextEdit(for: item)
            try await model.send(.fileInbox(item.id, decision))
            finish(item: item, draft: filed, target: target)
        } catch let error as GTDError {
            handle(error, decision: decision, target: target)
        } catch {
            lastError = .invalid("\(error)")
        }
    }

    /// The raw text is editable on the card (I2). For Knowledge the capture file *becomes* the
    /// note and for Trash it is moved as is, so an edit has to reach the file before it moves.
    private func persistTextEdit(for item: InboxItem) async throws {
        let edited = draft.text
        guard edited != item.text else { return }
        try await model.send(.editInboxText(item.id, edited))
    }

    private func finish(item: InboxItem, draft filed: Draft, target: CardTarget) {
        history.append((item: item, draft: filed, target: target))
        queue.removeAll { $0.id == item.id }
        processed += 1
        counts[target, default: 0] += 1
        sheet = nil
        pending = nil
        capCandidates = []
        validation = nil
        // Whoever filed a card in one of the four directions has understood the hint.
        if target.isDirect { dismissSwipeHint() }
        syncDraft()
    }

    private func handle(_ error: GTDError, decision: InboxDecision, target: CardTarget) {
        switch error {
        case .nextCapReached:
            // Forced choice, never automatic (ARCHITECTURE §6): the card springs back and the
            // sheet lists the current Next items.
            pending = (decision, target)
            capCandidates = Rules.nextList(model.snapshot, today: today)
            sheet = .cap
        default:
            lastError = error
        }
    }

    private func fail(_ issue: Validation.Issue) {
        validation = Validation(issue: issue, nonce: (validation?.nonce ?? 0) + 1)
    }

    /// Keeps `draft` attached to the card at the head of the queue.
    private func syncDraft() {
        guard draftItemID != current?.id else { return }
        draft = current.map(Draft.init(item:)) ?? Draft()
        draftItemID = current?.id
        validation = nil
    }

    /// The Someday version of a refused decision (the cap sheet's second option).
    static func demoted(_ decision: InboxDecision) -> InboxDecision {
        switch decision {
        case let .action(draft):
            return .action(demoted(draft))
        case let .newProject(project, firstActions):
            return .newProject(project, firstActions: firstActions.map(demoted))
        case let .existingProject(id, actions):
            return .existingProject(id, actions: actions.map(demoted))
        case .knowledge, .list, .trash:
            // A list item is not a commitment (L1), so the cap never applies to it.
            return decision
        }
    }

    private static func demoted(_ draft: ActionDraft) -> ActionDraft {
        guard draft.status.countsTowardCap else { return draft }
        var copy = draft
        copy.status = .someday
        return copy
    }
}
