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
