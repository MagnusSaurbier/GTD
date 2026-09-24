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
/// action card the inbox uses** (`MakeActionModel` over the action, `MovePlan.card`), the
/// defer-date sheet (Deferred is a date, R-2) or the project picker (the Projects section).
/// Once that dialogue confirms, the note sits in its new category; cancelling leaves it where
/// it was. Free of SwiftUI so the flow is unit-tested; `moveNoteHost(_:)` is its view.
@MainActor
@Observable
public final class MoveCoordinator {

    /// The dialogue a drop opened, `nil` while none is up.
    public enum Dialogue: Identifiable {
        /// `MovePlan.card` — the action card, aimed at the tier that was dropped on.
        case card(MakeActionModel)
        /// `MovePlan.deferDate`.
        case deferDate(Action)
        /// `MovePlan.pickProject`.
        case pickProject(Action)

        public var id: String {
            switch self {
            case let .card(model): "card:\(model.source.id.path)"
            case let .deferDate(action): "defer:\(action.id.path)"
            case let .pickProject(action): "project:\(action.id.path)"
            }
        }

        public var action: NoteID {
            switch self {
            case let .card(model): model.source.id
            case let .deferDate(action), let .pickProject(action): action.id
            }
        }
    }

    public var dialogue: Dialogue?

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
        case .deferDate:
            dialogue = .deferDate(action)
        case .pickProject:
            dialogue = .pickProject(action)
        }
    }

    /// The defer-date sheet's `Done`. A cleared date is a "not deferred after all" and is
    /// written as such (§1: undecided is empty).
    public func confirmDefer(_ action: Action, date: Day?) async {
        dialogue = nil
        var updated = action
        updated.deferDate = date
        await model.perform(.updateAction(updated))
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
