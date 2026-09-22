import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// One inbox-processing session (I1–I7): LIFO queue, one card at a time, no skipping, exit only
/// by quitting. Plain and unit-testable — **no SwiftUI**.
///
/// Since the rework it is an explicit **state machine** over `InboxStep` (I2, STYLEGUIDE
/// §3.5/§3.6): the small step-1 card decides the *kind*, and one of the two opened cards decides
/// the rest. Every gesture, key and VoiceOver action funnels into `take(_:)`, which refuses an
/// exit that does not belong to the current step instead of quietly doing it — that is what keeps
/// Trash and `Defer to review` reachable from step 1 only.
///
/// Views hold no decision logic: they render `step`, `draft`, `exits`, `sheet` and `queue`, and
/// call back in.
@MainActor
@Observable
public final class InboxSession {

    /// The draft type, named here too so a call site reads as "the session's draft".
    public typealias Draft = InboxDraft

    /// The sub-flows and the cap choice, as the sheet the card is showing (I4).
    public enum Sheet: String, Sendable, Equatable, Identifiable, CaseIterable {
        /// The Knowledge folder tree + the `Projects` section (I4b).
        case knowledge
        /// The `+ project` chip's picker (I4a).
        case project
        case waiting
        case deferToReview
        /// `Next is full` — demote one, or cancel. Never automatic (D14).
        case cap
        /// `More…` — every list, for the navbar's last slot.
        case more

        public var id: String { rawValue }
    }

    /// The last refusal, with a `nonce` that changes on every one so a repeated refusal animates
    /// again. The card shakes and marks the fields — never an alert (STYLEGUIDE §3.6, §4.3).
    public struct Refused: Sendable, Equatable {
        public var reason: InboxRefusal
        public var nonce: Int

        public init(reason: InboxRefusal, nonce: Int) {
            self.reason = reason
            self.nonce = nonce
        }
    }

    /// What `Esc` did — the ladder of STYLEGUIDE §3.6: focused field → blur; opened card →
    /// collapse; step 1 → quit. The view owns the focus and the way out, so it acts on this.
    public enum EscapeOutcome: Sendable, Equatable {
        case blurField
        case collapsed
        case quit
    }

    // MARK: - State

    /// Which of the three cards is on screen (I2). The only place it changes is `take(_:)` /
    /// `collapse()` / `undo()`.
    public private(set) var step: InboxStep = .step1

    public private(set) var queue: [InboxItem]
    /// The card being worked on, or `nil` when the session is finished (inbox zero).
    public var current: InboxItem? { queue.first }

    /// Draft, validation flags and cap state of the current card — the same value type
    /// `MakeActionModel` drives, so neither re-implements a rule (`ActionCard.swift`).
    public var card: ActionCardState

    /// The current card's draft. Views bind straight to it.
    public var draft: InboxDraft {
        get { card.draft }
        set { card.draft = newValue }
    }

    /// STYLEGUIDE §3.6 — while a text field has the keyboard, swipes and single keys are off.
    /// The view sets this; `DragResolver` and `KeyMap` are asked through the session.
    public var isFieldFocused: Bool {
        get { card.isFieldFocused }
        set { card.isFieldFocused = newValue }
    }

    public var sheet: Sheet?
    public private(set) var processed: Int
    public private(set) var refusal: Refused?

    /// The device's key map (R-10, N7). The app passes the stored value; tests and previews get
    /// the defaults.
    public var keyBindings: KeyBindings

    /// Which navbar the Knowledge / List card is showing — four favourite slots on iPhone,
    /// eight on Mac (STYLEGUIDE §3.6). The shell sets it.
    public var platform: NavbarPlatform

    /// The one-time direction hint of STYLEGUIDE §3.6, shown the **first time an action card
    /// opens** (there is nothing to hint at on the small card). **Stored**, so that dismissing it
    /// invalidates the view — the defaults flag behind it is not observable.
    public private(set) var isSwipeHintVisible: Bool = false

    /// Why `New list…` said no (`createListAndFile(name:)`), shown under the name field of the
    /// `More…` sheet. `nil` once the name changes, the list is made or the sheet is cancelled.
    public private(set) var newListRefusal: String?

    private let model: AppModel
    private let defaults: any InboxDefaultsStore
    private let now: () -> Date
    private let startedAt: Date
    private var draftItemID: NoteID?
    /// Renames the title field made this session, original id → current id (`persistEdits`).
    private var renamedIDs: [NoteID: NoteID] = [:]
    private var counts: [CardTarget: Int] = [:]
    /// True until the hint has been shown once on this device.
    private var hintPending: Bool

    /// One entry per filed card, so undo can put the card back **in the step it was filed from,
    /// with its draft intact** (R-9, I6, N6).
    private struct Filing {
        var item: InboxItem
        var card: ActionCardState
        var step: InboxStep
        var target: CardTarget
        var toastLabel: String
    }
    private var history: [Filing] = []

    public init(
        model: AppModel,
        defaults: any InboxDefaultsStore = InboxDefaults.shared,
        bindings: KeyBindings = .defaults,
        platform: NavbarPlatform = .iPhone,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = model
        self.defaults = defaults
        self.keyBindings = bindings
        self.platform = platform
        self.now = now
        self.startedAt = now()
        let items = Rules.inboxQueue(model.snapshot)
        self.queue = items
        self.processed = 0
        self.hintPending = !defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint)
        self.card = ActionCardState(draft: items.first.map(InboxDraft.init(item:)) ?? InboxDraft())
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

    /// The toast's wording, in the canonical form of STYLEGUIDE §6.3 (`Moved to Someday`,
    /// `Added to Read`). `nil` when there is nothing to undo.
    public var undoToastLabel: String? {
        guard canUndo, let last = history.last else { return nil }
        return last.toastLabel
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

    public var knowledgeFolders: [String] { model.snapshot.knowledgeFolders }

    /// I4b/D36 — the active projects whose folders the Knowledge picker offers as targets.
    public var activeProjects: [Project] {
        model.snapshot.projects
            .filter { $0.status == .active }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The Knowledge sheet's whole model: the suggested folder, the tree, and the `Projects`
    /// section (I4b, STYLEGUIDE §3.6).
    public var knowledgePicker: KnowledgePickerModel {
        KnowledgeTree.model(
            folders: knowledgeFolders,
            projects: activeProjects,
            suggestion: suggestedKnowledgeFolder)
    }

    /// The `+ project` picker's model for a search text (I4a).
    public func projectPicker(search: String = "") -> ProjectPickerModel {
        ProjectPicker.model(model.snapshot, search: search)
    }

    /// Kept for the picker's grouped tree without a search.
    public var projectGroups: [ProjectGroup] { ProjectPicker.groups(model.snapshot) }

    /// The navbar of the Knowledge / List card: `Knowledge`, the favourites in the user's order
    /// clipped to the platform limit, then `More…` (STYLEGUIDE §3.6, I4b).
    public var navbarSlots: [NavbarSlot] {
        NavbarLayout.slots(
            favourites: Rules.favouriteLists(model.snapshot).map(\.name),
            platform: platform)
    }

    /// Every list, for the `More…` sheet (§5a).
    public var allLists: [GTDList] { Rules.lists(model.snapshot) }

    /// True when the vault has no list at all — `Lists/` is empty or missing. The `More…` sheet
    /// then explains what a list is and offers `New list…` instead of an empty table.
    public var hasNoLists: Bool { allLists.isEmpty }

    /// The vault folder whose subfolders are the lists (L2) — named in the empty state.
    public var listsFolderName: String { model.snapshot.config.layout.lists }

    /// The favourite lists' names, in the user's order — what the navbar's fixed slots are
    /// built from (`DesignSystem.KnowledgeListNavbar`/`NavbarLayout`). Kept here so the view
    /// asks the session for data rather than calling `Rules` itself.
    public var favouriteListNames: [String] { Rules.favouriteLists(model.snapshot).map(\.name) }

    // MARK: - Validation flags (STYLEGUIDE §3.6)

    /// The fields the card marks with an asterisk right now, in `RequiredField` order. A field
    /// the user has since filled drops out by itself.
    public var missingFields: [RequiredField] { card.missingFields }

    /// Whether this one field's label wears the asterisk.
    public func isMissing(_ field: RequiredField) -> Bool { card.isMissing(field) }

    /// Bumped on every refusal — drives `View.shake(trigger:)` and the `.error` haptic.
    public var shakeTrigger: Int { card.shakeTrigger }

    /// The first missing **text** field, for the card to focus. `nil` when only a chip group is
    /// missing.
    public var focusRequest: RequiredField? { card.focusRequest }

    /// The card took the focus request; it is not asked for again.
    public func consumeFocusRequest() { card.clearFocusRequest() }

    /// The Next items offered for demotion while the cap sheet is up (I4, A3).
    public var capCandidates: [Action] { card.capCandidates }

    /// An error that is neither the cap nor a validation issue (a title collision, say).
    public var lastError: GTDError? { card.lastError }

    public func clearError() { card.lastError = nil }

    // MARK: - Exits of the current step (I4, STYLEGUIDE §3.6)

    /// Every exit the current step offers, in the order the style guide's table lists them. This
    /// is what VoiceOver exposes as custom actions ("VoiceOver exposes every exit of the current
    /// step as a custom action") and what a bar or a menu is built from.
    public var exits: [InboxExit] { exits(of: step) }

    public func exits(of step: InboxStep) -> [InboxExit] {
        switch step {
        case .step1:
            return [.openAction, .openKeep, .trash, .deferToReview]
        case .actionCard:
            return [.next, .someday, .waiting, .done, .collapse]
        case .keepCard:
            return navbarSlots.map { slot in
                switch slot.kind {
                case .knowledge: InboxExit.knowledge
                case let .list(name): InboxExit.list(name)
                case .more: InboxExit.more
                }
            } + [.collapse]
        }
    }

    /// True when `exit` can be taken right now. `take(_:)` refuses anything else.
    public func canTake(_ exit: InboxExit) -> Bool {
        if exit == .collapse { return step.isOpened }
        if case .list = exit { return step == .keepCard }
        return exit.step == step
    }

    // MARK: - The state machine

    /// The single entry point for a swipe, a key, a bar button and a VoiceOver action alike
    /// (STYLEGUIDE §3.6). An exit that does not belong to the current step is **refused**.
    public func take(_ exit: InboxExit) async {
        guard current != nil else {
            refuse(.noCard)
            return
        }
        guard canTake(exit) else {
            refuse(.notAvailable(exit, in: step))
            return
        }
        switch exit {
        case .openAction:
            open(.actionCard)
        case .openKeep:
            open(.keepCard)
        case .trash:
            await fileDecision(.trash, as: .trash)
        case .deferToReview:
            sheet = .deferToReview
        case .next:
            await fileAction(status: .next, as: .next)
        case .someday:
            await fileAction(status: .someday, as: .someday)
        case .waiting:
            sheet = .waiting
        case .done:
            await fileAction(status: .done, as: .done)
        case .knowledge:
            sheet = .knowledge
        case let .list(name):
            await confirmList(name: name)
        case .more:
            sheet = .more
        case .collapse:
            collapse()
        }
    }

    /// Expands the card in place (STYLEGUIDE §3.5: never a new screen, never a sheet). The draft
    /// is whatever the card already carries — reopening after a collapse shows it again.
    private func open(_ target: InboxStep) {
        step = target
        refusal = nil
        // The one-time hint belongs to the swipes, which only the action card has.
        if target == .actionCard, hintPending {
            hintPending = false
            isSwipeHintVisible = true
            defaults.setFlag(true, forKey: InboxDefaultsKey.didShowSwipeHint)
        }
    }

    /// `↓` / `Esc` on an opened card: back to step 1. **Everything already typed stays** — the
    /// draft survives until the card is filed or the session ends (STYLEGUIDE §3.6).
    public func collapse() {
        guard step.isOpened else { return }
        step = .step1
        sheet = nil
        card.clearCap()
        refusal = nil
    }

    /// `Esc` is a ladder: focused field → blur; opened card → collapse; step 1 → quit
    /// (STYLEGUIDE §3.6 "Always"). The session takes the step it owns and tells the view what
    /// happened, because focus and "quit" are the view's.
    @discardableResult
    public func escape() -> EscapeOutcome {
        if isFieldFocused {
            isFieldFocused = false
            return .blurField
        }
        if step.isOpened {
            collapse()
            return .collapsed
        }
        return .quit
    }

    // MARK: - Queue

    /// New captures that arrived mid-session go on top (LIFO, I7), and items that left the inbox
    /// elsewhere (another device, the weekly review) disappear from the queue.
    ///
    /// One refinement over a literal "always on top": a card the user is **already working on** —
    /// opened, or with something typed into it — is not yanked away; a fresh capture is then
    /// queued directly behind it and processed next.
    public func refresh() {
        let live = Rules.inboxQueue(model.snapshot)
        let liveByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        let known = Set(queue.map(\.id))
        let fresh = live.filter { !known.contains($0.id) }

        // Keep the order the session established, but pick up remote text edits.
        var kept = queue.compactMap { liveByID[$0.id] }

        if let head = kept.first, let current, head.id == current.id, isWorkingOnCurrentCard {
            kept.insert(contentsOf: fresh, at: 1)
            queue = kept
        } else {
            queue = fresh + kept
        }
        syncDraft()
    }

    /// True when the card shows the note's body under its title: the stored body has something
    /// in it — the empty Why/What template skeleton of an Obsidian-made note does not count
    /// (`CaptureText.isEmptyBody`). Decided on the stored body, not the draft, so the field does
    /// not vanish while the user clears it.
    public var showsBody: Bool {
        guard let current else { return false }
        return !CaptureText.isEmptyBody(current.body)
    }

    private var isWorkingOnCurrentCard: Bool {
        guard let current else { return false }
        return step.isOpened || !draft.isPristine(for: current)
    }

    // MARK: - Filing

    /// Next / Someday / Waiting / Done — the four exits that create an action (I4).
    private func fileAction(
        status: ActionStatus, waiting: WaitingInfo? = nil, as target: CardTarget
    ) async {
        guard let item = current else {
            refuse(.noCard)
            return
        }
        let filedStep = step
        let filedCard = card
        // The title field may rename the file first; from then on the card is the renamed note.
        var filedID = item.id
        let result = await ActionCardEngine.file(
            state: card, status: status, waiting: waiting, model: model,
            send: { payload in
                filedID = try await self.persistEdits(for: item.id)
                try await self.model.send(.fileInbox(filedID, .action(payload)))
            })
        let filed = item.renamed(to: filedID)
        adopt(result.state, for: filed)
        switch result.outcome {
        case .filed:
            finish(item: filed, card: filedCard, step: filedStep, target: target,
                   toastLabel: target.undoToastLabel())
        case let .refused(reason):
            present(reason)
        }
    }

    /// Trash, Knowledge and the lists — the exits that need nothing and create no action.
    private func fileDecision(
        _ decision: InboxDecision, as target: CardTarget, toastLabel: String? = nil
    ) async {
        guard let item = current else {
            refuse(.noCard)
            return
        }
        let filedStep = step
        let filedCard = card
        do {
            let filedID = try await persistEdits(for: item.id)
            try await model.send(.fileInbox(filedID, decision))
            card.clearFlags()
            card.clearCap()
            finish(item: item.renamed(to: filedID), card: filedCard, step: filedStep, target: target,
                   toastLabel: toastLabel ?? target.undoToastLabel())
        } catch let error as GTDError {
            card.lastError = error
            refuse(.failed(error))
        } catch {
            let wrapped = GTDError.invalid("\(error)")
            card.lastError = wrapped
            refuse(.failed(wrapped))
        }
    }

    /// The title and the body are editable on the card. The filed note keeps the inbox note's
    /// file name and body, so both edits have to reach the file before it is filed: the body
    /// first (`editInboxBody`), then the title, which **renames** the file within `Inbox/`
    /// (`renameInboxItem`; a taken name is a `.titleCollision`, an empty one is refused).
    ///
    /// Returns the id the note has now. Re-read from the snapshot and resolved through the
    /// renames this session made, so a cap retry neither sends an edit twice nor files under the
    /// old name. The queue follows the rename at once, so a `refresh()` — the cap sheet, a
    /// failed filing — keeps the card and its draft instead of treating the renamed note as new.
    private func persistEdits(for original: NoteID) async throws -> NoteID {
        let id = renamedIDs[original] ?? original
        guard let stored = model.snapshot.inboxItem(id) else { return id }
        if draft.body != stored.body {
            try await model.send(.editInboxBody(id, draft.body))
        }
        guard CaptureText.renamedTitle(draft.title) != stored.title else { return id }
        try await model.send(.renameInboxItem(id, title: draft.title))
        // The reducer refused anything it could not name, so the name exists here.
        let target = model.snapshot.config.layout.inboxPath(
            title: CaptureText.renamedTitle(draft.title) ?? stored.title)
        follow(id, to: target)
        renamedIDs[original] = target
        return target
    }

    /// Points the queue and the card at a renamed note, keeping its place and its draft.
    private func follow(_ old: NoteID, to new: NoteID) {
        guard let renamed = model.snapshot.inboxItem(new) else { return }
        queue = queue.map { $0.id == old ? renamed : $0 }
        if draftItemID == old { draftItemID = new }
    }

    // MARK: - Sub-flows

    /// I4b — Knowledge: the capture file becomes the knowledge note, with the notes panel (and
    /// the full capture text above it when the title had to cut it) as its body. The folder is
    /// remembered on this device so the next card can *suggest* it.
    public func confirmKnowledge(target: KnowledgeTarget, notes: String? = nil) async {
        if case let .folder(folder) = target {
            defaults.setString(folder, forKey: InboxDefaultsKey.lastKnowledgeFolder)
        }
        await fileDecision(.knowledge(target, notes: notes ?? draft.notes), as: .knowledge)
    }

    /// I4b/§5a — the capture becomes one item of a list. Not a commitment, so nothing is
    /// required; the navbar files at once (STYLEGUIDE §3.6).
    public func confirmList(name: String, notes: String? = nil) async {
        await fileDecision(
            .list(name: name, notes: notes ?? draft.notes),
            as: .list,
            toastLabel: CardTarget.list.undoToastLabel(listName: name))
    }

    /// `More…` › `New list…` — creates the list (L2: the folder `Lists/<name>/`) and files the
    /// card into it, exactly as picking an existing list does. The reducer owns what a valid
    /// name is (empty, the reserved `Done`, a list that already exists); its refusal stays in
    /// the sheet as `newListRefusal`, next to the field, and the card does not move.
    ///
    /// Undo takes the card back out of the list; the list itself stays, because `createList`
    /// has no inverse (`Rules.isUndoable`) — an empty folder costs nothing.
    @discardableResult
    public func createListAndFile(name: String) async -> Bool {
        guard step == .keepCard, current != nil else {
            refuse(current == nil ? .noCard : .notAvailable(.more, in: step))
            return false
        }
        do {
            try await model.send(.createList(name: name))
        } catch let error as GTDError {
            newListRefusal = InboxCopy.newListRefusal(for: error)
            return false
        } catch {
            newListRefusal = Copy.actionFailed
            return false
        }
        newListRefusal = nil
        // The reducer sanitises the name; file into the list it actually made.
        let created = model.snapshot.list(named: VaultLayout.sanitize(name))?.name
            ?? VaultLayout.sanitize(name)
        await confirmList(name: created)
        // A filing that failed has said so on the card (`lastError`); the sheet is done either way.
        sheet = nil
        return true
    }

    /// Typing again takes the refusal away — it described the previous name.
    public func clearNewListRefusal() { newListRefusal = nil }

    /// W1/D39 — the follow-up date is required, who is optional; both arrive confirmed.
    public func confirmWaiting(_ info: WaitingInfo) async {
        guard step == .actionCard else {
            refuse(.notAvailable(.waiting, in: step))
            return
        }
        await fileAction(status: .waiting, waiting: info, as: .waiting)
    }

    /// I4a/R-8 — the `+ project` chip.
    public func chooseProject(_ id: NoteID?) { card.draft.chooseProject(id) }

    /// The picker's `Create project "<text>"` row: the project is created with a name only, in
    /// the same command that files the card (R-8).
    public func createProject(named title: String) { card.draft.createProject(named: title) }

    /// What the chip shows: the chosen project's title, the name being created, or `nil`.
    public func projectChipTitle(in snapshot: VaultSnapshot) -> String? {
        draft.projectChipTitle(in: snapshot)
    }

    /// I5 — the escape hatch, step 1 only. The reason is required; the item leaves the queue and
    /// shows up in the weekly review with its reason.
    public func confirmDeferToReview(reason: String) async {
        guard step == .step1 else {
            refuse(.notAvailable(.deferToReview, in: step))
            return
        }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            refuse(.reasonRequired)
            return
        }
        guard let item = current else {
            refuse(.noCard)
            return
        }
        let filedCard = card
        do {
            let deferredID = try await persistEdits(for: item.id)
            try await model.send(.deferInboxToReview(deferredID, reason: trimmed))
            finish(item: item.renamed(to: deferredID), card: filedCard, step: .step1, target: .deferToReview,
                   toastLabel: CardTarget.deferToReview.undoToastLabel())
        } catch let error as GTDError {
            card.lastError = error
            refuse(.failed(error))
        } catch {
            let wrapped = GTDError.invalid("\(error)")
            card.lastError = wrapped
            refuse(.failed(wrapped))
        }
    }

    // MARK: - Cap (A3, I4)

    /// Demote one of the current Next items and file the card that was refused. The other half of
    /// the forced choice is `cancelSheet()` — there is no "send to Someday instead" (D14).
    public func demoteAndRetry(_ id: NoteID) async {
        guard let item = current, card.pending != nil else { return }
        let filedStep = step
        let filedCard = card
        var filedID = item.id
        guard let result = await ActionCardEngine.demoteAndRetry(
            state: card, demoting: id, model: model,
            send: { payload in
                filedID = try await self.persistEdits(for: item.id)
                try await self.model.send(.fileInbox(filedID, .action(payload)))
            })
        else { return }
        let filed = item.renamed(to: filedID)
        adopt(result.state, for: filed)
        switch result.outcome {
        case let .filed(payload):
            sheet = nil
            let target: CardTarget = payload.status == .waiting
                ? .waiting
                : (CardTarget.allCases.first { $0.status == payload.status } ?? .next)
            finish(item: filed, card: filedCard, step: filedStep, target: target,
                   toastLabel: target.undoToastLabel())
        case let .refused(reason):
            present(reason)
        }
    }

    /// Closes a sub-flow sheet without filing anything. The card, its step and its draft stay.
    public func cancelSheet() {
        sheet = nil
        newListRefusal = nil
        card.clearCap()
    }

    // MARK: - Undo (R-9, I6, N6)

    /// Undo the last card. Per R-9 it comes back **at the head of the queue, in the step it was
    /// filed from, with its draft intact**: the opened action card for Next / Someday / Waiting /
    /// Done, the opened Knowledge / List card for a list or Knowledge filing, and the small card
    /// for Trash and Defer to review.
    public func undo() async {
        guard let last = history.popLast() else { return }
        await model.undo()
        refresh()

        guard let restored = model.snapshot.inboxItem(last.item.id), restored.reviewReason == nil
        else {
            // The backend refused the undo — leave the session consistent with the vault.
            history.append(last)
            syncDraft()
            return
        }

        queue.removeAll { $0.id == restored.id }
        queue.insert(restored, at: 0)
        card = last.card
        card.clearCap()
        draftItemID = restored.id
        step = last.step

        processed = max(processed - 1, 0)
        counts[last.target] = max((counts[last.target] ?? 1) - 1, 0)
        sheet = nil
        refusal = nil
    }

    // MARK: - Swipe hint (STYLEGUIDE §3.6)

    /// Hides the one-time hint for good: the stored property invalidates the view, the flag —
    /// already written when the hint appeared — keeps it away in the next session.
    public func dismissSwipeHint() {
        guard isSwipeHintVisible else { return }
        isSwipeHintVisible = false
    }

    // MARK: - Keys (STYLEGUIDE §3.6, Mac)

    /// Resolves and performs one key press for the **current step**, through the device's
    /// bindings (R-10). Returns `false` when nothing on this step uses the key, so the view can
    /// report `.ignored`. A press while a field has the keyboard is always ignored except `Esc`.
    @discardableResult
    public func handle(
        character: Character, shift: Bool = false, command: Bool = false
    ) async -> Bool {
        guard let key = KeyMap.resolve(
            character, shift: shift, command: command, step: step, bindings: keyBindings)
        else { return false }
        return await handle(key)
    }

    /// The same for a key that already is a `KeyStroke` — the arrows, and anything a legend row
    /// spells.
    @discardableResult
    public func handle(stroke: KeyStroke) async -> Bool {
        guard let key = KeyMap.resolve(stroke: stroke, step: step, bindings: keyBindings)
        else { return false }
        return await handle(key)
    }

    /// Performs an already-resolved key. `escape()` is the one thing that works while a field is
    /// focused (it is what blurs it).
    @discardableResult
    public func handle(_ key: InboxKey) async -> Bool {
        if case .escape = key {
            escape()
            return true
        }
        guard !isFieldFocused else { return false }
        switch key {
        case let .command(command):
            return await perform(command)
        case let .context(index):
            guard index < contexts.count else { return false }
            toggleContext(contexts[index])
            return true
        case let .time(bucket):
            card.draft.timeBucket = card.draft.timeBucket == bucket ? nil : bucket
            return true
        case .done:
            await take(.done)
            return true
        case .undo:
            await undo()
            return true
        case .escape:
            return true
        }
    }

    private func perform(_ command: KeyCommand) async -> Bool {
        switch command {
        case .stepAction: await take(.openAction)
        case .stepKnowledge: await take(.openKeep)
        case .stepTrash: await take(.trash)
        case .stepDefer: await take(.deferToReview)
        case .cardNext: await take(.next)
        case .cardSomeday: await take(.someday)
        case .cardWaiting: await take(.waiting)
        // R-8 — `P` opens the project chip's picker; it never files the card.
        case .cardProject: sheet = .project
        case .listKnowledge: await take(.knowledge)
        case .listMore: await take(.more)
        case .listSlot2, .listSlot3, .listSlot4, .listSlot5,
             .listSlot6, .listSlot7, .listSlot8, .listSlot9:
            guard let index = KeyCommand.knowledgeListFavouriteSlots.firstIndex(of: command),
                  let slot = navbarSlots.first(where: { $0.keyIndex == index + 2 }),
                  case let .list(name) = slot.kind
            else { return false }
            await take(.list(name))
        case .deckKeep, .deckDemote, .deckPromote, .deckTrash:
            // Another screen's commands — `KeyMap` never returns one here, and if a stored table
            // ever did, the inbox ignores it rather than guessing.
            return false
        }
        return true
    }

    public func toggleContext(_ context: String) {
        if let index = card.draft.contexts.firstIndex(of: context) {
            card.draft.contexts.remove(at: index)
        } else {
            card.draft.contexts.append(context)
        }
    }

    // MARK: - Legend (STYLEGUIDE §3.6 Mac — "the legend always renders the current bindings")

    /// The current step's legend rows, keys first. Built from `KeyBindings`, so a rebind in
    /// Settings › Keyboard changes the legend without a line changing here.
    public var legend: [KeyBindings.LegendEntry] {
        switch step {
        case .step1:
            return keyBindings.legend(for: .inboxStep1, titles: [
                .stepAction: Copy.actionKind,
                .stepKnowledge: Copy.knowledgeOrList,
                .stepTrash: Copy.trash,
                .stepDefer: Copy.deferToReview,
            ])
        case .actionCard:
            let directions = keyBindings.legend(for: .actionCard, titles: [
                .cardSomeday: Copy.someday,
                .cardNext: Copy.next,
            ])
            let rest = keyBindings.legend(for: .actionCard, titles: [
                .cardWaiting: Copy.waiting,
                .cardProject: Copy.project,
            ])
            // `⌘↩ Done` and `Esc Back` are fixed keys, not commands (`KeyBindings.fixedKeys`).
            let done = KeyBindings.LegendEntry(
                key: KeyStroke.commandReturn.display, label: Copy.done)
            let back = KeyBindings.LegendEntry(key: KeyStroke.escape.display, label: Copy.back)
            // `W Waiting · ⌘↩ Done · P Project · Esc Back` — `Done` sits between the two
            // commands, so the two halves are interleaved rather than concatenated.
            guard rest.count == 2 else { return directions + rest + [done, back] }
            return directions + [rest[0], done, rest[1], back]
        case .keepCard:
            var titles: [KeyCommand: String] = [
                .listKnowledge: Copy.knowledge,
                .listMore: Copy.more,
            ]
            for slot in navbarSlots {
                guard case let .list(name) = slot.kind,
                      slot.keyIndex >= 2,
                      slot.keyIndex - 2 < KeyCommand.knowledgeListFavouriteSlots.count
                else { continue }
                titles[KeyCommand.knowledgeListFavouriteSlots[slot.keyIndex - 2]] = name
            }
            let rows = keyBindings.legend(for: .knowledgeListCard, titles: titles)
            return rows + [
                KeyBindings.LegendEntry(key: KeyStroke.escape.display, label: Copy.back),
            ]
        }
    }

    /// The legend as STYLEGUIDE §3.6 prints it. The action card's row keeps its two groups: the
    /// commitment axis, wide space, then the rest.
    public var legendString: String {
        func join(_ rows: [KeyBindings.LegendEntry], _ separator: String) -> String {
            rows.map { "\($0.key) \($0.label)" }.joined(separator: separator)
        }
        guard step == .actionCard else { return join(legend, " · ") }
        let rows = legend
        return join(Array(rows.prefix(2)), "  ") + "    " + join(Array(rows.dropFirst(2)), " · ")
    }

    // MARK: - Drag (STYLEGUIDE §3.6)

    /// What the drag map is allowed to see right now: the step, and whether a field has the
    /// keyboard. Views pass it straight to `DragResolver` instead of re-deciding either.
    public var dragContext: DragContext {
        DragContext(step: step, isFieldFocused: isFieldFocused)
    }

    /// Performs a completed drag (`DragResolver.outcome`).
    public func perform(_ outcome: DragOutcome) async {
        switch outcome {
        case let .file(exit): await take(exit)
        case .collapse: collapse()
        }
    }

    // MARK: - Internals

    private func finish(
        item: InboxItem, card filedCard: ActionCardState, step filedStep: InboxStep,
        target: CardTarget, toastLabel: String
    ) {
        history.append(
            Filing(item: item, card: filedCard, step: filedStep, target: target,
                   toastLabel: toastLabel))
        queue.removeAll { $0.id == item.id }
        processed += 1
        counts[target, default: 0] += 1
        sheet = nil
        refusal = nil
        // Whoever filed a card along the commitment axis has understood the hint.
        if target == .next || target == .someday { dismissSwipeHint() }
        step = .step1
        syncDraft()
    }

    /// Takes the engine's state back after an awaited filing — unless the session has moved on.
    /// The view calls `refresh()` whenever the inbox changes, also *during* that await; by then
    /// `card` already belongs to the next item, and the filed card's state must never reach it
    /// (it would show, and file, the previous capture's text).
    private func adopt(_ state: ActionCardState, for item: InboxItem) {
        guard draftItemID == item.id else { return }
        card = state
    }

    private func present(_ reason: InboxRefusal) {
        if case .capReached = reason { sheet = .cap }
        refuse(reason)
    }

    private func refuse(_ reason: InboxRefusal) {
        refusal = Refused(reason: reason, nonce: (refusal?.nonce ?? 0) + 1)
    }

    /// Keeps `card` attached to the item at the head of the queue. A fresh card always starts at
    /// step 1 with an empty draft — nothing of the last one leaks into it.
    private func syncDraft() {
        guard draftItemID != current?.id else { return }
        card = ActionCardState(draft: current.map(InboxDraft.init(item:)) ?? InboxDraft())
        draftItemID = current?.id
        refusal = nil
        step = .step1
    }
}

private extension InboxItem {
    /// The same note under the id a rename gave it.
    func renamed(to id: NoteID) -> InboxItem {
        guard id != self.id else { return self }
        return InboxItem(
            id: id, body: body, created: created, reviewReason: reviewReason,
            passthrough: passthrough)
    }
}
