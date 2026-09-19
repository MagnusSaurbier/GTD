import Foundation
import GTDModel

/// What the undo toast says the last command was (STYLEGUIDE §3.8, §6.3).
///
/// The wording is the style guide's fixed vocabulary — `Moved to Backlog`, `Filed to Next`,
/// `Completed <title>` — and it is deliberately identical, word for word, to
/// `InMemoryBackend`'s, so the toast reads the same whether a screen runs on fixtures or on the
/// real vault. `ParityTests.undoLabelsAgree` pins the two together after every command.
///
/// T16 was briefed with `Filed 'Call bank' to Next`; STYLEGUIDE §3.8/§6.3 spell the toast
/// `Moved to Backlog` without the note's title, and the style guide wins on wording
/// (ARCHITECTURE §5). Only `complete` names its note, because both backends already did.
enum UndoLabel {

    static func of(_ command: GTDCommand, in snapshot: VaultSnapshot) -> String {
        switch command {
        case let .fileInbox(_, decision):
            switch decision {
            case let .action(draft): "Filed to \(tier(draft.status))"
            case .knowledge: "Filed to Knowledge"
            case .newProject, .existingProject: "Filed to Project"
            case .trash: "Moved to Trash"
            }
        case let .setStatus(_, status, _):
            "Moved to \(tier(status))"
        case let .complete(id):
            "Completed \(snapshot.action(id)?.title ?? "action")"
        case .createAction: "Created action"
        case .createProject, .convertActionToProject: "Created project"
        case .createArea: "Created area"
        case .promoteStep: "Promoted step"
        case .deferInboxToReview: "Deferred to review"
        case .toggleCheckbox: "Toggled checkbox"
        case .updateAction, .updateProject, .editInboxText: "Edited"
        case .saveWeeklyReview, .logRoutineStep, .setRoutineTime, .updateConfig, .archiveCompleted:
            // Not undoable (`Rules.isUndoable`); never reaches the toast.
            "Last change"
        }
    }

    /// The tier names of STYLEGUIDE §6.2. `in-progress` is part of Next.
    private static func tier(_ status: ActionStatus) -> String {
        switch status {
        case .next, .inProgress: "Next"
        case .backlog: "Backlog"
        case .maybe: "Maybe"
        case .waiting: "Waiting"
        case .done: "Done"
        case .trash: "Trash"
        }
    }
}
