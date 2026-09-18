import Foundation
import GTDModel

/// What the UI is allowed to know about the store. Two implementations exist:
/// `InMemoryBackend` (here, reducer only — previews and tests) and `GTDServices.VaultBackend`
/// (the real vault). Features never see either type; they hold `AppModel`.
public protocol GTDBackend: Sendable {
    /// Emits on every local or remote change. The first element is the current snapshot.
    func snapshots() -> AsyncStream<VaultSnapshot>

    /// The snapshot as of right now. Added by T00 so `AppModel.send` can update deterministically
    /// instead of racing the stream (ARCHITECTURE §4, contract change T00-2).
    func currentSnapshot() async -> VaultSnapshot

    /// Runs one command. Throws `GTDError` for anything the UI must handle (cap, waiting info…).
    func perform(_ command: GTDCommand) async throws -> [AppPrompt]

    /// N6 — reverts the last filing/status change.
    func undo() async throws

    /// Human-readable label of what `undo()` would revert, or `nil` when there is nothing.
    func undoLabel() async -> String?
}
