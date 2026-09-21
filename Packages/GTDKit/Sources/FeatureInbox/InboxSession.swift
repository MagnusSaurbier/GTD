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
        /// The captured text, editable in place — and, since R-4, the **title** as well: the
        /// note is named after its first line and keeps the whole text in its body.
        public var text: String
        public var why: String
        public var what: String
        public var contexts: [String]
        public var timeBucket: TimeBucket?
        public var deferDate: Day?
        public var due: Day?
        /// I4a — the `+ project` chip: an existing project…
        public var project: NoteID?
        /// …or one the picker is creating with this name (R-8). Never both.
        public var newProjectTitle: String?

        public init(
            text: String = "",
            why: String = "",
            what: String = "",
            contexts: [String] = [],
            timeBucket: TimeBucket? = nil,
            deferDate: Day? = nil,
            due: Day? = nil,
            project: NoteID? = nil,
            newProjectTitle: String? = nil
        ) {
            self.text = text
            self.why = why
            self.what = what
            self.contexts = contexts
            self.timeBucket = timeBucket
            self.deferDate = deferDate
            self.due = due
            self.project = project
            self.newProjectTitle = newProjectTitle
        }

        public init(item: InboxItem) {
            self.init(text: item.text)
        }

        /// R-4 — the file name this card would get, for the card to show. `nil` while the
        /// capture is only whitespace, which is the one thing that cannot be filed.
        public var noteTitle: String? { CaptureText.title(of: text) }

        /// A2 — a second checkbox in *What?* offers "Turn into project".
        public var suggestsProject: Bool { Checkbox.scan(what).count >= 2 }

        /// True while the user has changed nothing about this card.
        public func isPristine(for item: InboxItem) -> Bool {
            self == Draft(item: item)
        }
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
            /// R-3/D12 — the tier the card is leaving to needs fields the draft does not have.
            /// Every one of them is listed, in `RequiredField` order, so the card can mark each.
            case missing([RequiredField])
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

    /// I4b/D36 — the active projects whose folders the Knowledge picker offers as targets.
    public var activeProjects: [Project] {
        model.snapshot.projects
            .filter { $0.status == .active }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

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
        case .next, .someday, .done:
            guard let status = target.status else { return }
            await file(.action(actionDraft(status: status)), as: target)
        case .trash:
            await file(.trash, as: .trash)
        case .knowledge:
            sheet = .knowledge
        case .waiting:
            sheet = .waiting
        case .deferToReview:
            sheet = .deferToReview
        }
    }

    /// Validation before leaving (STYLEGUIDE §3.6, R-3): Next needs `Why?`, `What?`, a context
    /// and a time estimate, Someday needs `What?`, Waiting needs `What?` and the sheet's date,
    /// and Done, Knowledge, lists and Trash need nothing. The reducer refuses anything that
    /// slips through — this only saves the round trip and marks the fields.
    @discardableResult
    public func validate(for target: CardTarget, waiting: WaitingInfo? = nil) -> Bool {
        guard let status = target.status else { return true }
        let missing = RequiredField.missing(
            status: status,
            previous: nil,
            why: draft.why,
            what: draft.what,
            contexts: draft.contexts,
            timeEstimate: draft.timeBucket?.minutes,
            followUpDate: waiting?.followUp)
        guard !missing.isEmpty else { return true }
        fail(.missing(missing))
        return false
    }

    /// The fields the card must mark with an asterisk right now (STYLEGUIDE §3.6).
    public var missingFields: [RequiredField] {
        guard case let .missing(fields) = validation?.issue else { return [] }
        return fields
    }

    /// I4b — Knowledge: the capture file becomes the knowledge note, with the notes panel (and
    /// the full capture text above it when the title had to cut it) as its body. The folder is
    /// remembered on this device so the next card can *suggest* it.
    public func confirmKnowledge(target: KnowledgeTarget, notes: String = "") async {
        if case let .folder(folder) = target {
            defaults.setString(folder, forKey: InboxDefaultsKey.lastKnowledgeFolder)
        }
        await file(.knowledge(target, notes: notes), as: .knowledge)
    }

    /// I4b/§5a — the capture becomes one item of a list. Not a commitment, so nothing is required.
    public func confirmList(name: String, notes: String = "") async {
        await file(.list(name: name, notes: notes), as: .knowledge)
    }

    /// W1/D39 — the follow-up date is required, who is optional; both arrive confirmed.
    public func confirmWaiting(_ info: WaitingInfo) async {
        guard validate(for: .waiting, waiting: info) else { return }
        await file(.action(actionDraft(status: .waiting, waiting: info)), as: .waiting)
    }

    /// I4a/R-8 — the `+ project` chip. The card **stays an action**: it names a project instead
    /// of turning into one (D33). Nothing is written until the card is filed.
    public func chooseProject(_ id: NoteID?) {
        draft.project = id
        draft.newProjectTitle = nil
    }

    /// The picker's `Create project "<text>"` row: the project is created with a name only, in
    /// the same command that files the card (R-8).
    public func createProject(named title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft.project = nil
        draft.newProjectTitle = clean
    }

    /// What the chip shows: the chosen project's title, the name being created, or `nil`.
    public func projectChipTitle(in snapshot: VaultSnapshot) -> String? {
        if let newProjectTitle = draft.newProjectTitle { return newProjectTitle }
        guard let id = draft.project else { return nil }
        return snapshot.project(id)?.title ?? id.title
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
            // R-4 — the reducer names the note after the capture text; what travels here is the
            // text the card shows, so the two can never disagree.
            title: draft.text,
            status: status,
            contexts: draft.contexts,
            timeEstimate: draft.timeBucket?.minutes,
            project: draft.project,
            newProjectTitle: draft.newProjectTitle,
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
            // sheet lists the current Next items to demote — or the user cancels. There is no
            // "send to Someday instead" shortcut (STYLEGUIDE §3.6).
            pending = (decision, target)
            capCandidates = Rules.nextList(model.snapshot, today: today)
            sheet = .cap
        case let .missingFields(fields):
            // R-3 — the reducer is the authority; the card marks what it named.
            fail(.missing(fields))
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

}
