import Testing
import Foundation
import GTDModel
@testable import GTDAppCore

/// STYLEGUIDE §3.8/§6.3 — the undo toast's wording, one table for both backends.
/// `ParityTests.undoLabelsAgree` pins that they agree; this pins what they say.
struct UndoLabelTests {

    private let snapshot = VaultSnapshot.empty
    private let id = NoteID(path: "Actions/Etwas.md")

    /// A3 — the single "not now" tier is called Someday, in the toast as everywhere else.
    @Test(arguments: [
        (ActionStatus.next, "Moved to Next"),
        (.inProgress, "Moved to Next"),
        (.someday, "Moved to Someday"),
        (.waiting, "Moved to Waiting"),
        (.done, "Moved to Done"),
    ])
    func aStatusChangeNamesItsTier(status: ActionStatus, label: String) {
        #expect(UndoLabel.of(.setStatus(id, status, waiting: nil), in: snapshot) == label)
    }

    @Test func filingAnInboxCardNamesWhereItWent() {
        #expect(UndoLabel.of(
            .fileInbox(id, .action(ActionDraft(title: "x", status: .someday))), in: snapshot)
                == "Filed to Someday")
        #expect(UndoLabel.of(
            .fileInbox(id, .action(ActionDraft(title: "x", status: .next))), in: snapshot)
                == "Filed to Next")
        #expect(UndoLabel.of(.fileInbox(id, .trash), in: snapshot) == "Moved to Trash")
    }

    /// I4c — trashing an action is its own command, and it says so.
    @Test func trashingAnActionSaysMovedToTrash() {
        #expect(UndoLabel.of(.trashAction(id), in: snapshot) == "Moved to Trash")
    }
}
