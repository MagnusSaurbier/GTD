import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// **Make action** (L4): the opened action card, alone, over one existing note.
///
/// `FeatureLists` presents STYLEGUIDE §3.5's step 2a on top of this — the same card, the same
/// draft, the same required fields and the same cap flow as the inbox, because all of that is
/// `ActionCardState` / `ActionCardEngine` and neither this type nor `InboxSession` owns a copy of
/// it. The only differences are what it starts from (a `Source`, not a capture), the command it
/// sends (`promoteListItem`, which *moves* the note out of `Lists/<n>/`, `promoteStep` for a
/// project step (P6), `createAction` for a new action typed into "What's next?" (P5), or `updateAction` for an action that was dropped onto a section it is not
/// ready for — `MovePlan.card`) and that
/// there is no step 1 to collapse to: the way out is `cancel()`, which leaves the note as it was.
///
/// The exits are the four of the action card: `→` Next, `←` Someday, `Waiting`, `Done`.
@MainActor
@Observable
public final class MakeActionModel {

    /// What the card is over. Nothing is written until `isFiled`.
    public enum Source: Sendable, Equatable {
        /// L4 — a list item being promoted; it stays in its list until filed.
        case listItem(ListItem)
        /// A drop (or `Move to…`) that needs fields the action does not have yet.
        case action(Action)
        /// P6 — an open step of a project, promoted from the project detail. The action is born
        /// in that project and the step points at it (`promoteStep`).
        case projectStep(project: NoteID, stepIndex: Int, text: String)
        /// P5 — a new action typed into "What's next?", born in `project`.
        case newProjectAction(project: NoteID, title: String)

        public var id: NoteID {
            switch self {
            case let .listItem(item): item.id
            case let .action(action): action.id
            case let .projectStep(project, _, _): project
            case let .newProjectAction(project, _): project
            }
        }
    }

    public let source: Source

    /// The list item being promoted (L4), `nil` when the card is over an action.
    public var item: ListItem? {
        if case let .listItem(item) = source { return item }
        return nil
    }

    /// The capture stamp the card shows (`InboxCopy.captureStamp`), when the note has one.
    public var created: Date? {
        switch source {
        case let .listItem(item): item.created
        case let .action(action): action.created
        case .projectStep, .newProjectAction: nil
        }
    }

    /// A promoted step or a "What's next?" action belongs to the project it came from — it is
    /// filed there whatever the draft says — so the card's project chip shows that project and
    /// cannot be changed.
    public var canChangeProject: Bool {
        switch source {
        case .projectStep, .newProjectAction: false
        case .listItem, .action: true
        }
    }

    /// Draft, validation flags and cap state — the inbox card's, unchanged.
    public var card: ActionCardState {
        // #94 — what is typed over a list item, a step or a "What's next?" line is kept.
        didSet { if card.draft != oldValue.draft { keepDraft() } }
    }

    /// The draft. Views bind straight to it.
    public var draft: InboxDraft {
        get { card.draft }
        set { card.draft = newValue }
    }

    /// STYLEGUIDE §3.6 — swipes and single keys are off while a field has the keyboard.
    public var isFieldFocused: Bool {
        get { card.isFieldFocused }
        set { card.isFieldFocused = newValue }
    }

    /// Always the opened action card: there is no step 1 here, so `DragResolver`/`KeyMap` see
    /// exactly what the inbox's step 2a sees.
    public let step: InboxStep = .actionCard

    /// `true` once the item has become an action — the host dismisses the card.
    public private(set) var isFiled = false

    /// The sheet a sub-flow is showing: `waiting`, `project` or the cap's forced choice.
    public var sheet: InboxSession.Sheet?

    public private(set) var refusal: InboxSession.Refused?

    public var keyBindings: KeyBindings

    private let model: AppModel

    public init(
        model: AppModel,
        item: ListItem,
        bindings: KeyBindings = .defaults
    ) {
        self.model = model
        self.source = .listItem(item)
        self.keyBindings = bindings
        self.card = ActionCardState(draft: InboxDraft(item: item))
        restoreDraft()
    }

    /// The card over an existing action that was dropped onto `target` and is not ready for it
    /// (`MovePlan.card`). It opens with the action's own values, the fields `target` still
    /// needs already marked (STYLEGUIDE §3.6's asterisks — no second refusal needed to see
    /// them), and, for Waiting, the follow-up sheet already up: the date is the only thing
    /// that tier can be missing on an existing action (W1/D39), so the card behind it is
    /// only there for the way back.
    public init(
        model: AppModel,
        action: Action,
        target: ActionStatus,
        missing: [RequiredField],
        bindings: KeyBindings = .defaults
    ) {
        self.model = model
        self.source = .action(action)
        self.keyBindings = bindings
        var card = ActionCardState(draft: InboxDraft(action: action), previousStatus: action.status)
        if !missing.isEmpty { card.flag(missing) }
        self.card = card
        if target == .waiting { sheet = .waiting }
    }

    /// #76 — the card over an existing action, opened from its status badge in a project's step
    /// list to change where it stands. It opens with the action's own values, nothing marked
    /// and no sub-sheet up; the exits file it like a drop would (`updateAction`).
    public init(
        model: AppModel,
        changingStatusOf action: Action,
        bindings: KeyBindings = .defaults
    ) {
        self.model = model
        self.source = .action(action)
        self.keyBindings = bindings
        self.card = ActionCardState(draft: InboxDraft(action: action), previousStatus: action.status)
    }

    /// P6 — the card over a project step. It opens with the step's line as the title and as
    /// `What?` (the step *is* the next physical action — the reducer uses the same default), and
    /// with the project on the project chip; everything else is asked for like any capture.
    public init(
        model: AppModel,
        project: NoteID,
        stepIndex: Int,
        stepText: String,
        bindings: KeyBindings = .defaults
    ) {
        self.model = model
        self.source = .projectStep(project: project, stepIndex: stepIndex, text: stepText)
        self.keyBindings = bindings
        self.card = ActionCardState(
            draft: InboxDraft(title: stepText, what: stepText, project: project))
        restoreDraft()
    }

    /// P5 — the card over a new action typed into "What's next?": the typed line is the title
    /// and `What?`, the project is the one being asked about.
    public init(
        model: AppModel,
        project: NoteID,
        newActionTitle: String,
        bindings: KeyBindings = .defaults
    ) {
        self.model = model
        self.source = .newProjectAction(project: project, title: newActionTitle)
        self.keyBindings = bindings
        self.card = ActionCardState(
            draft: InboxDraft(title: newActionTitle, what: newActionTitle, project: project))
        restoreDraft()
    }

    // MARK: - Derived

    public var snapshot: VaultSnapshot { model.snapshot }
    public var today: Day { model.today() }
    public var contexts: [String] { model.snapshot.config.contexts }

    /// The four exits of the opened action card, for VoiceOver and the bar. `collapse` is not
    /// among them — there is nothing to collapse to (see `cancel()`).
    public var exits: [InboxExit] { [.next, .someday, .waiting, .done] }

    public var missingFields: [RequiredField] { card.missingFields }
    public func isMissing(_ field: RequiredField) -> Bool { card.isMissing(field) }
    public var shakeTrigger: Int { card.shakeTrigger }
    public var focusRequest: RequiredField? { card.focusRequest }
    public func consumeFocusRequest() { card.clearFocusRequest() }
    public var capCandidates: [Action] { card.capCandidates }
    public var lastError: GTDError? { card.lastError }
    public func clearError() { card.lastError = nil }

    public var dragContext: DragContext {
        DragContext(step: step, isFieldFocused: isFieldFocused)
    }

    public func projectPicker(search: String = "") -> ProjectPickerModel {
        ProjectPicker.model(model.snapshot, search: search)
    }

    /// The Mac legend of the opened action card, from the current bindings.
    public var legend: [KeyBindings.LegendEntry] {
        let directions = keyBindings.legend(for: .actionCard, titles: [
            .cardSomeday: Copy.someday,
            .cardNext: Copy.next,
        ])
        let rest = keyBindings.legend(for: .actionCard, titles: [
            .cardWaiting: Copy.waiting,
            .cardProject: Copy.project,
        ])
        let done = KeyBindings.LegendEntry(key: KeyStroke.commandReturn.display, label: Copy.done)
        guard rest.count == 2 else { return directions + rest + [done] }
        return directions + [rest[0], done, rest[1]]
    }

    // MARK: - Exits

    /// The single entry point, exactly as `InboxSession.take(_:)`. Anything but the four exits of
    /// the action card is refused.
    public func take(_ exit: InboxExit) async {
        guard exits.contains(exit) else {
            refuse(.notAvailable(exit, in: step))
            return
        }
        switch exit {
        case .next: await file(status: .next)
        case .someday: await file(status: .someday)
        case .waiting: sheet = .waiting
        case .done: await file(status: .done)
        default: refuse(.notAvailable(exit, in: step))
        }
    }

    /// W1/D39 — the follow-up date is required, who is optional.
    public func confirmWaiting(_ info: WaitingInfo) async {
        await file(status: .waiting, waiting: info)
    }

    public func chooseProject(_ id: NoteID?) {
        guard canChangeProject else { return }
        card.draft.chooseProject(id)
    }
    public func createProject(named title: String) {
        guard canChangeProject else { return }
        card.draft.createProject(named: title)
    }
    public func projectChipTitle(in snapshot: VaultSnapshot) -> String? {
        draft.projectChipTitle(in: snapshot)
    }

    /// The cap's forced choice: demote one Next item and file. The other half is `cancelSheet()`.
    public func demoteAndRetry(_ id: NoteID) async {
        guard card.pending != nil else { return }
        guard let result = await ActionCardEngine.demoteAndRetry(
            state: card, demoting: id, model: model, send: send)
        else { return }
        card = result.state
        apply(result.outcome)
    }

    /// Closes a sub-flow sheet without filing. The draft stays.
    public func cancelSheet() {
        sheet = nil
        card.clearCap()
    }

    /// The way out: the item stays where it is, in its list, and nothing was written.
    public func cancel() {
        sheet = nil
        card.clearCap()
        card.clearFlags()
    }

    // MARK: - Drafts over notes without action fields (#94)

    /// Where the card keeps what is typed when its note has no place for action fields — a
    /// list item (L1: only its notes), a project step (only its line), a "What's next?" line
    /// (no note yet). `nil` over an existing action: that one keeps its edits in the action
    /// itself (`keptEdits`, #85).
    public var draftKey: String? {
        switch source {
        case let .listItem(item): InputDraftKey.makeActionOverListItem(item.id)
        case let .projectStep(project, _, text): InputDraftKey.makeActionOverStep(project: project, text: text)
        case let .newProjectAction(project, title):
            InputDraftKey.makeActionOverWhatsNext(project: project, title: title)
        case .action: nil
        }
    }

    /// The key the card's follow-up sheet keeps its `who` and date under.
    public var waitingDraftKey: String? {
        if case let .action(action) = source { return InputDraftKey.waiting(action.id) }
        return draftKey.map(InputDraftKey.waiting)
    }

    /// The drafts store the card's sheets keep their fields in.
    public var inputDrafts: InputDrafts { model.inputDrafts }

    /// The draft the card opened with, before anything was typed or restored.
    @ObservationIgnored private var openingDraft: InboxDraft?

    /// The card opens with what was typed over the same note the last time it was left —
    /// `Close`, `Esc`, a swipe, ⌘Q, a crash — without filing. Every way out keeps it: this
    /// card has no `Cancel`, only `Close`. Filing clears it.
    private func restoreDraft() {
        openingDraft = card.draft
        guard let draftKey, let saved = model.inputDrafts.value(InboxDraft.self, for: draftKey) else { return }
        card.draft = saved
    }

    private func keepDraft() {
        guard let draftKey, !isFiled, let openingDraft else { return }
        model.inputDrafts.keep(card.draft == openingDraft ? nil : card.draft, for: draftKey)
    }

    // MARK: - Closing keeps the edits (#85)

    /// What closing the card without filing writes, or `nil` when it writes nothing.
    ///
    /// Over an existing action (a drop, `Move to…`, a step's status badge) the fields typed or
    /// chosen are kept in the action — title, `Why?`/`What?`, chips, dates, an existing project —
    /// and only the move is cancelled: status and the waiting pair stay the note's own. Built
    /// on the action **as the vault has it now**, so a field changed elsewhere meanwhile and
    /// not touched on the card is not reverted. A project the picker was about to create is not
    /// created. The other sources have nowhere to keep action fields — a list item carries only
    /// its notes (L1), a step only its line, "What's next?" nothing yet — so they keep nothing.
    public var keptEdits: Action? {
        guard !isFiled, case let .action(original) = source,
              let current = model.snapshot.action(original.id) else { return nil }
        let start = InboxDraft(action: original)
        var edited = current
        func take<V: Equatable>(_ path: WritableKeyPath<InboxDraft, V>, into apply: (V) -> Void) {
            if draft[keyPath: path] != start[keyPath: path] { apply(draft[keyPath: path]) }
        }
        take(\.title) { edited.title = $0 }
        take(\.body) { edited.preamble = $0 }
        take(\.why) { edited.why = $0 }
        take(\.what) { edited.what = $0 }
        take(\.contexts) { edited.contexts = $0 }
        take(\.timeBucket) { edited.timeEstimate = $0?.minutes }
        take(\.deferDate) { edited.deferDate = $0 }
        take(\.due) { edited.due = $0 }
        if draft.newProjectTitle == nil { take(\.project) { edited.project = $0 } }
        return edited == current ? nil : edited
    }

    /// #85 — writes `keptEdits` (`updateAction`). A refusal reaches the shell's alert. Harmless
    /// to call twice: the second call finds nothing left to write.
    public func keepEdits() async {
        guard let edited = keptEdits else { return }
        await model.perform(.updateAction(edited))
    }

    // MARK: - Keys

    @discardableResult
    public func handle(
        character: Character, shift: Bool = false, command: Bool = false
    ) async -> Bool {
        guard let key = KeyMap.resolve(
            character, shift: shift, command: command, step: step, bindings: keyBindings)
        else { return false }
        return await handle(key)
    }

    @discardableResult
    public func handle(stroke: KeyStroke) async -> Bool {
        guard let key = KeyMap.resolve(stroke: stroke, step: step, bindings: keyBindings)
        else { return false }
        return await handle(key)
    }

    /// The `Esc` ladder, one rung shorter than the inbox's: focused field → blur, otherwise
    /// `cancel()` — there is no step 1 under this card to collapse to. The host dismisses on
    /// `isFiled == false`, which says nothing was written.
    @discardableResult
    public func handle(_ key: InboxKey) async -> Bool {
        if case .escape = key {
            if isFieldFocused {
                isFieldFocused = false
            } else {
                cancel()
            }
            return true
        }
        guard !isFieldFocused else { return false }
        switch key {
        case let .command(command):
            switch command {
            case .cardNext: await take(.next)
            case .cardSomeday: await take(.someday)
            case .cardWaiting: await take(.waiting)
            case .cardProject:
                guard canChangeProject else { return false }
                sheet = .project
            default: return false
            }
            return true
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
        case .undo, .escape:
            // Undo belongs to the list this card came from, not to the card.
            return false
        }
    }

    public func toggleContext(_ context: String) {
        if let index = card.draft.contexts.firstIndex(of: context) {
            card.draft.contexts.remove(at: index)
        } else {
            card.draft.contexts.append(context)
        }
    }

    // MARK: - Internals

    private func file(status: ActionStatus, waiting: WaitingInfo? = nil) async {
        let result = await ActionCardEngine.file(
            state: card, status: status, waiting: waiting, model: model, send: send)
        card = result.state
        apply(result.outcome)
    }

    private func send(_ payload: ActionDraft) async throws {
        switch source {
        case let .listItem(item):
            try await model.send(.promoteListItem(item.id, payload))
        case let .projectStep(project, stepIndex, _):
            try await model.send(.promoteStep(project: project, stepIndex: stepIndex, payload))
        case let .newProjectAction(project, _):
            var payload = payload
            payload.project = project
            payload.newProjectTitle = nil
            try await model.send(.createAction(payload))
        case let .action(action):
            var payload = payload
            if let title = payload.newProjectTitle {
                try await model.send(.createProject(ProjectDraft(title: title)))
                payload.project = model.snapshot.config.layout.projectPath(title: title, inArea: nil)
                payload.newProjectTitle = nil
            }
            try await model.send(.updateAction(updated(action, with: payload)))
        }
    }

    /// The action as the card would write it: the draft's values over the note's own, the
    /// waiting pair from the sheet. `updateAction` runs the same `normalize` as a filing
    /// (required fields, the cap, an inactive project), so every refusal comes back the same
    /// way. A project created from the picker (R-8) is born first, by its own command, because
    /// `updateAction` names projects and never creates them.
    private func updated(_ action: Action, with payload: ActionDraft) -> Action {
        var updated = action
        updated.title = payload.title
        updated.status = payload.status
        updated.contexts = payload.contexts
        updated.timeEstimate = payload.timeEstimate
        updated.project = payload.project
        updated.deferDate = payload.deferDate
        updated.due = payload.due
        updated.waitingFor = payload.waiting?.who
        updated.followUpDate = payload.waiting?.followUp
        updated.why = payload.why
        updated.what = payload.what
        return updated
    }

    private func apply(_ outcome: ActionCardEngine.Outcome) {
        switch outcome {
        case .filed:
            sheet = nil
            refusal = nil
            isFiled = true
            // #94 — filed: the kept draft and the follow-up sheet's have done their job.
            if let draftKey { model.inputDrafts.clear(draftKey) }
            if let waitingDraftKey { model.inputDrafts.clear(waitingDraftKey) }
        case let .refused(reason):
            if case .capReached = reason { sheet = .cap }
            refuse(reason)
        }
    }

    private func refuse(_ reason: InboxRefusal) {
        refusal = InboxSession.Refused(reason: reason, nonce: (refusal?.nonce ?? 0) + 1)
    }
}
