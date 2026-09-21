import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// **Make action** (L4): the opened action card, alone, for one list item.
///
/// `FeatureLists` presents STYLEGUIDE §3.5's step 2a on top of this — the same card, the same
/// draft, the same required fields and the same cap flow as the inbox, because all of that is
/// `ActionCardState` / `ActionCardEngine` and neither this type nor `InboxSession` owns a copy of
/// it. The only differences are what it starts from (a `ListItem`, not a capture), the command it
/// sends (`promoteListItem`, which *moves* the note out of `Lists/<n>/`) and that there is no
/// step 1 to collapse to: the way out is `cancel()`, which leaves the item in its list.
///
/// The exits are the four of the action card: `→` Next, `←` Someday, `Waiting`, `Done`.
@MainActor
@Observable
public final class MakeActionModel {

    /// The item being promoted; it stays in its list until `isFiled`.
    public let item: ListItem

    /// Draft, validation flags and cap state — the inbox card's, unchanged.
    public var card: ActionCardState

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
        self.item = item
        self.keyBindings = bindings
        self.card = ActionCardState(draft: InboxDraft(item: item))
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

    public func chooseProject(_ id: NoteID?) { card.draft.chooseProject(id) }
    public func createProject(named title: String) { card.draft.createProject(named: title) }
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
            case .cardProject: sheet = .project
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
        try await model.send(.promoteListItem(item.id, payload))
    }

    private func apply(_ outcome: ActionCardEngine.Outcome) {
        switch outcome {
        case .filed:
            sheet = nil
            refusal = nil
            isFiled = true
        case let .refused(reason):
            if case .capReached = reason { sheet = .cap }
            refuse(reason)
        }
    }

    private func refuse(_ reason: InboxRefusal) {
        refusal = InboxSession.Refused(reason: reason, nonce: (refusal?.nonce ?? 0) + 1)
    }
}
