import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox

/// The Lists home and one list's items (§5a, L1–L6): counts, the open/finished split, `Done`,
/// `Trash` and the entry point into **Make action** (L4). Plain and unit-testable — **no
/// SwiftUI**. The title/notes editor is a separate model, `ListItemEditModel`, mirroring the
/// `ActionListModel` / `ActionEditModel` split in `FeatureOverview`.
@MainActor
@Observable
public final class ListsModel {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var snapshot: VaultSnapshot { model.snapshot }

    /// The Lists home / Mac sidebar section rows, in `Rules.lists(_:)` order (L2, L5).
    public var rows: [Rules.ListRow] { Rules.listRows(snapshot) }

    /// Open items across every list — the iPhone tab badge and the Mac sidebar row's count (L5).
    public var totalOpenCount: Int { Rules.openListItemCount(snapshot) }

    /// A list's open items, newest capture first (L1).
    public func openItems(in list: String) -> [ListItem] {
        Rules.listItems(snapshot, in: list, finished: false)
    }

    /// A list's finished items — `Lists/<name>/Done/` (L3), shown behind `Show done`.
    public func finishedItems(in list: String) -> [ListItem] {
        Rules.listItems(snapshot, in: list, finished: true)
    }

    // MARK: - Adding (L1)

    /// The `+` inside a list: one new open item in `list`, stamped now. Whitespace around the
    /// title is dropped here so the view's "nothing typed yet" and the reducer's `titleRequired`
    /// agree; an empty title, an unknown list or a taken title come back as `false` through
    /// `AppModel.perform`, so the shell's alert says why.
    @discardableResult
    public func add(_ title: String, to list: String, notes: String = "") async -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return await model.perform(.addListItem(list: list, title: clean, notes: notes))
    }

    /// What the sheet's `Add` button disables on: nothing but whitespace typed.
    public static func canAdd(_ title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Row commands

    /// Moves the item to `Lists/<name>/Done/` (L3). Undoable, so a mis-swipe is never final.
    @discardableResult
    public func complete(_ id: NoteID) async -> Bool {
        await model.perform(.completeListItem(id))
    }

    /// I4c — moves the item to `GTD/Trash/`, never a hard delete.
    @discardableResult
    public func trash(_ id: NoteID) async -> Bool {
        await model.perform(.trashListItem(id))
    }

    // MARK: - Make action (L4)

    /// The opened action card, driven by the same `MakeActionModel` the design brief asks for —
    /// no decision about it lives here or in the view that presents it.
    public func makeActionModel(for item: ListItem) -> MakeActionModel {
        MakeActionModel(model: model, item: item)
    }
}
