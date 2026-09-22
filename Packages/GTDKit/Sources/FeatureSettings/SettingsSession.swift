import Foundation
import Observation
import GTDModel
import GTDAppCore

/// Sends every synced-settings edit as a `GTDCommand.updateConfig` or `.setRoutineTime`. Plain
/// and unit-testable — **no SwiftUI** (same shape as `RoutineRun` / `WaitingListModel`). Owned
/// by T26.
@MainActor
@Observable
public final class SettingsSession {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var config: GTDConfig { model.snapshot.config }
    public var routines: [Routine] { model.snapshot.routines }
    public var issues: [VaultIssue] { model.snapshot.issues }

    // MARK: Contexts (A4)

    /// Actions still tagged with `context` — shown before a removal is confirmed.
    public func affectedActionCount(for context: String) -> Int {
        ContextsEditing.affectedActionCount(for: context, in: model.snapshot.actions)
    }

    public func addContext(_ name: String) async throws {
        try await model.send(.updateConfig(ContextsEditing.adding(name, to: config)))
    }

    public func renameContext(_ old: String, to new: String) async throws {
        try await model.send(.updateConfig(ContextsEditing.renaming(old, to: new, in: config)))
    }

    public func removeContext(_ name: String) async throws {
        try await model.send(.updateConfig(ContextsEditing.removing(name, from: config)))
    }

    public func reorderContexts(from source: IndexSet, to destination: Int) async throws {
        try await model.send(.updateConfig(ContextsEditing.reordering(config, from: source, to: destination)))
    }

    public func toggleOnTheGo(_ name: String) async throws {
        try await model.send(.updateConfig(ContextsEditing.togglingOnTheGo(name, in: config)))
    }

    // MARK: Lists (L2, R-5)

    /// Every list, alphabetically, with its open/finished counts (`Rules.listRows`).
    public var listRows: [Rules.ListRow] { Rules.listRows(model.snapshot) }

    /// The effective favourites, in order: the stored choice, or — while nothing has been
    /// chosen — the derived default (first four alphabetically), both via `Rules.favouriteLists`.
    /// A stored name whose folder is gone (removed or renamed outside the app) is left out, so
    /// the next `toggleFavourite`/`reorderFavourites` drops it from `GTD/Config.md`. Reading
    /// this never writes `favouriteLists` (R-5's "never written until the user changes
    /// something").
    public var favouriteListNames: [String] {
        Rules.favouriteLists(model.snapshot).map(\.name)
    }

    /// Lists not currently a favourite — what `addFavourite`'s picker offers.
    public var listsAvailableToFavourite: [String] {
        let chosen = Set(favouriteListNames.map { $0.lowercased() })
        return listRows.map(\.list.name).filter { !chosen.contains($0.lowercased()) }
    }

    /// Open + finished items a removal's `confirmationDialog` names (R-5: "takes items with it").
    public func itemCount(inList name: String) -> Int {
        guard let row = listRows.first(where: { GTDList.sameName($0.list.name, name) }) else { return 0 }
        return row.openCount + row.finishedCount
    }

    public func createList(_ name: String) async throws {
        try await model.send(.createList(name: name))
    }

    public func renameList(_ old: String, to new: String) async throws {
        try await model.send(.renameList(from: old, to: new))
    }

    public func removeList(_ name: String) async throws {
        try await model.send(.removeList(name: name))
    }

    /// Adds `name` to the favourites or removes it, capped at `ListsEditing.storageLimit`
    /// (`ListsEditing.FavouriteError.limitReached` when adding past it). The first toggle turns
    /// the shown derived default into a stored choice.
    public func toggleFavourite(_ name: String) async throws {
        let next = try ListsEditing.toggling(name, in: favouriteListNames)
        try await model.send(.setFavouriteLists(next))
    }

    /// Reorders the favourites the way `List.onMove` reports a drag.
    public func reorderFavourites(from source: IndexSet, to destination: Int) async throws {
        let next = ListsEditing.reordering(favouriteListNames, from: source, to: destination)
        try await model.send(.setFavouriteLists(next))
    }

    // MARK: Next cap (A3)

    /// Rethrows `GTDError.invalid` for cap <= 0 (`Reducer.updateConfig`) — the UI never
    /// pre-clamps, so the same validation lives in one place.
    public func setNextCap(_ cap: Int) async throws {
        var next = config
        next.nextCap = cap
        try await model.send(.updateConfig(next))
    }

    // MARK: Routines (R3)

    public func setRoutineTime(_ routine: NoteID, to time: DayTime?) async throws {
        try await model.send(.setRoutineTime(routine: routine, time))
    }
}
