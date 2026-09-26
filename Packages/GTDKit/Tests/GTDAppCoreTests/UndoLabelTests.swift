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
        #expect(UndoLabel.of(.fileInbox(id, .knowledge(.folder("Studium"), notes: "")), in: snapshot)
                == "Filed to Knowledge")
        // I4/D13 — the 2-minute rule: the card is done, and the toast says so (§6.3).
        #expect(UndoLabel.of(
            .fileInbox(id, .action(ActionDraft(title: "x", status: .done))), in: snapshot) == "Done")
    }

    /// E3 — an action dropped on a list reads like an inbox card filed there (§6.3).
    @Test func movingAnActionToAListNamesTheList() {
        #expect(UndoLabel.of(.moveActionToList(id, list: "Read"), in: snapshot) == "Added to Read")
    }

    /// I4c — trashing an action is its own command, and it says so.
    @Test func trashingAnActionSaysMovedToTrash() {
        #expect(UndoLabel.of(.trashAction(id), in: snapshot) == "Moved to Trash")
    }

    // MARK: - Lists (§5a, STYLEGUIDE §6.3)

    /// §6.3 spells the list toast with the list's own name: `Added to Read`.
    @Test func filingToAListNamesTheList() {
        #expect(UndoLabel.of(
            .fileInbox(id, .list(name: "Read", notes: "")), in: snapshot)
                == "Added to Read")
        #expect(UndoLabel.of(
            .fileInbox(id, .list(name: "Wish", notes: "")), in: snapshot)
                == "Added to Wish")
    }

    /// L1 — an item typed inside a list reads like an inbox filing into it.
    @Test func addingAListItemSaysAddedToTheList() {
        #expect(UndoLabel.of(.addListItem(list: "Read", title: "Sapiens", notes: ""), in: snapshot)
            == "Added to Read")
    }

    /// §6.3 — a finished list item is just `Done`.
    @Test func finishingAListItemSaysDone() {
        let item = NoteID(path: "Lists/Read/Sapiens.md")
        #expect(UndoLabel.of(.completeListItem(item), in: snapshot) == "Done")
        #expect(UndoLabel.of(.trashListItem(item), in: snapshot) == "Moved to Trash")
    }

    /// L4 — "Make action" is a filing like any other, and reads like one.
    @Test func promotingAListItemReadsLikeAFiling() {
        let item = NoteID(path: "Lists/Read/Sapiens.md")
        #expect(UndoLabel.of(
            .promoteListItem(item, ActionDraft(title: "Read Sapiens", status: .next)), in: snapshot)
                == "Filed to Next")
        #expect(UndoLabel.of(
            .promoteListItem(item, ActionDraft(title: "Read Sapiens", status: .someday)), in: snapshot)
                == "Filed to Someday")
    }

    @Test func theFolderCommandsSayWhatTheyDid() {
        #expect(UndoLabel.of(.renameList(from: "Read", to: "Reading"), in: snapshot) == "Renamed list")
        #expect(UndoLabel.of(.removeList(name: "Read"), in: snapshot) == "Removed list")
        #expect(UndoLabel.of(
            .updateListItem(NoteID(path: "Lists/Read/Sapiens.md"), title: "x", notes: ""),
            in: snapshot) == "Edited")
    }
}
