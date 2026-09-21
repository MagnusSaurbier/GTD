import Foundation
import GTDModel

/// What the undo toast says the last command was (STYLEGUIDE §3.8, §6.3).
///
/// The wording is the style guide's fixed vocabulary — `Moved to Someday`, `Filed to Next`,
/// `Completed <title>`. It lives here, in `GTDAppCore`, so `InMemoryBackend` and
/// `GTDServices.VaultBackend` read the *same* table rather than two copies of it: the toast is
/// then identical by construction whether a screen runs on fixtures or on the real vault
/// (T41; `ParityTests.undoLabelsAgree` still pins it after every command).
///
/// T16 was briefed with `Filed 'Call bank' to Next`; STYLEGUIDE §3.8/§6.3 spell the toast
/// `Moved to Someday` without the note's title, and the style guide wins on wording
/// (ARCHITECTURE §5). Only `complete` names its note, because both backends already did.
public enum UndoLabel {

    public static func of(_ command: GTDCommand, in snapshot: VaultSnapshot) -> String {
        switch command {
        case let .fileInbox(_, decision):
            switch decision {
            // I4/D13 — the 2-minute rule files the card as done; `Done` is the word
            // STYLEGUIDE §6.3 uses for something that is finished, with or without a title.
            case let .action(draft): draft.status == .done ? "Done" : "Filed to \(tier(draft.status))"
            case .knowledge: "Filed to Knowledge"
            // STYLEGUIDE §6.3 spells this one with the list's name: `Added to Read`.
            case let .list(name, _): "Added to \(name)"
            case .trash: "Moved to Trash"
            }
        case let .setStatus(_, status, _):
            "Moved to \(tier(status))"
        case .trashAction:
            "Moved to Trash"
        case let .complete(id):
            "Completed \(snapshot.action(id)?.title ?? "action")"
        case .createAction: "Created action"
        case .createProject, .convertActionToProject: "Created project"
        case .createArea: "Created area"
        case .promoteStep: "Promoted step"
        case .deferInboxToReview: "Deferred to review"

        // §5a — the list commands. `Done` is STYLEGUIDE §6.3's wording for a finished list item;
        // a promoted one reads like any other filing, because that is exactly what it is (L4).
        case .completeListItem: "Done"
        case .trashListItem: "Moved to Trash"
        case let .promoteListItem(_, draft): "Filed to \(tier(draft.status))"
        case .renameList: "Renamed list"
        case .removeList: "Removed list"
        case .updateListItem: "Edited"
        case .createList, .setFavouriteLists, .pruneFavouriteLists:
            // Not undoable (`Rules.isUndoable`); never reaches the toast.
            "Last change"
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
        case .someday: "Someday"
        case .waiting: "Waiting"
        case .done: "Done"
        case .legacyTrashed: "Trash"
        }
    }
}
