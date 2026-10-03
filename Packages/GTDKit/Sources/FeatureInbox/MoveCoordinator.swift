import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Dragging a row onto a category (E3) — or its `Move to…` twin: one place that turns a drop
/// into what `MovePlan` says has to happen, and holds the dialogue while it is up.
///
/// A drop that needs nothing goes straight to `AppModel.perform` (a refusal reaches the
/// shell's alert; the undo toast covers the move). A drop that needs more opens **the same
/// action card the inbox uses** (`MakeActionModel` over the action, `MovePlan.card`) or the
/// project picker (the Projects section). There is no Deferred target: deferring is moving to
/// Waiting with a follow-up date and no who (#86).
/// Once that dialogue confirms, the note sits in its new category; cancelling leaves it where
/// it was. Free of SwiftUI so the flow is unit-tested; `moveNoteHost(_:)` is its view.
@MainActor
@Observable
public final class MoveCoordinator {

    /// The dialogue a drop opened, `nil` while none is up.
    public enum Dialogue: Identifiable {
        /// `MovePlan.card` — the action card, aimed at the tier that was dropped on.
        case card(MakeActionModel)
        /// `MovePlan.pickProject`.
        case pickProject(Action)
        /// `MovePlan.pickList` — the inbox's list picker (`More…`), over an action.
        case pickList(Action)

        public var id: String {
            switch self {
            case let .card(model): "card:\(model.source.id.path)"
            case let .pickProject(action): "project:\(action.id.path)"
            case let .pickList(action): "list:\(action.id.path)"
            }
        }

        public var action: NoteID {
            switch self {
            case let .card(model): model.source.id
            case let .pickProject(action), let .pickList(action): action.id
            }
        }
    }

    public var dialogue: Dialogue?

    /// The note last picked up by a drag in this window (`MoveNoteHandler.beginDrag`), so a
    /// drop target can say while it hovers whether it would accept it. Not cleared at the
    /// drag's end — the drag API has no end hook — and only ever read during a hover.
    public var dragging: NoteID?

    /// The Mac key table the card legend shows; the host keeps it current.
    public var keyBindings: KeyBindings

    private let model: AppModel

    public init(model: AppModel, bindings: KeyBindings = .defaults) {
        self.model = model
        self.keyBindings = bindings
    }

    /// The drop highlight: whether `destination` would do anything for this note.
    public func accepts(_ id: NoteID, _ destination: MoveDestination) -> Bool {
        guard let action = model.snapshot.action(id) else { return false }
        return MovePlan.accepts(
            action: action, destination: destination, snapshot: model.snapshot, today: model.today())
    }

    /// The drop. Returns once the move is done or its dialogue is up.
    public func move(_ id: NoteID, to destination: MoveDestination) async {
        guard let action = model.snapshot.action(id) else { return }
        switch MovePlan.plan(
            action: action, to: destination, snapshot: model.snapshot, today: model.today())
        {
        case .alreadyThere:
            return
        case let .perform(command):
            await model.perform(command)
        case let .card(status, missing):
            dialogue = .card(MakeActionModel(
                model: model, action: action, target: status, missing: missing,
                bindings: keyBindings))
        case .pickProject:
            dialogue = .pickProject(action)
        case .pickList:
            newListRefusal = nil
            dialogue = .pickList(action)
        }
    }

    // MARK: Lists

    /// Every list, for the picker (§5a) — the same rows as the inbox's `More…` sheet.
    public var allLists: [GTDList] { Rules.lists(model.snapshot) }
    public var hasNoLists: Bool { allLists.isEmpty }
    public var listsFolderName: String { model.snapshot.config.layout.lists }

    /// The picker's `New list…` refusal (an empty or reserved name), shown next to the field.
    public private(set) var newListRefusal: String?
    public func clearNewListRefusal() { newListRefusal = nil }

    /// The list picker's choice: the action becomes an item of `name` (`moveActionToList`).
    public func chooseList(_ action: Action, named name: String) async {
        dialogue = nil
        await model.perform(.moveActionToList(action.id, list: name))
    }

    /// `New list…` — creates the list and moves the action into it, exactly as picking an
    /// existing one does (`InboxSession.createListAndFile`). A refused name keeps the sheet
    /// open with the reason; the action stays where it is.
    @discardableResult
    public func createListAndMove(_ action: Action, named name: String) async -> Bool {
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
        let created = model.snapshot.list(named: VaultLayout.sanitize(name))?.name
            ?? VaultLayout.sanitize(name)
        await chooseList(action, named: created)
        return true
    }

    /// The project picker's choice: attach `project`, replacing what the action named before
    /// (an action names one project); `nil` clears it.
    public func chooseProject(_ action: Action, _ project: NoteID?) async {
        dialogue = nil
        var updated = action
        updated.project = project
        await model.perform(.updateAction(updated))
    }

    /// The picker's `Create project "<title>"` row (R-8): the project is born by its own
    /// command, then attached like any other.
    public func createProject(_ action: Action, named title: String) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard await model.perform(.createProject(ProjectDraft(title: clean))) else {
            dialogue = nil
            return
        }
        let id = model.snapshot.config.layout.projectPath(title: clean, inArea: nil)
        await chooseProject(action, id)
    }

    /// The project picker's rows for `search`.
    public func projectPicker(search: String = "") -> ProjectPickerModel {
        ProjectPicker.model(model.snapshot, search: search)
    }

    /// Closes whatever is up without writing anything.
    public func cancel() { dialogue = nil }

    public var today: Day { model.today() }
}
