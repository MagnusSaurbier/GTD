import Foundation
import GTDModel

/// One published state of the vault: the snapshot, plus what the change that produced it did to
/// note *identities*.
///
/// A backend publishes this and nothing else, so a consumer can never see the snapshot of a
/// rename without the rename itself — which is the whole point: the difference between a note
/// that was deleted and one that is now called something else is not in the snapshot
/// (`RenameMap`). `renames` is empty for every update that renamed nothing, including every
/// snapshot that came from a rescan of the files.
public struct SnapshotUpdate: Sendable, Equatable {
    public var snapshot: VaultSnapshot
    public var renames: RenameMap

    public init(snapshot: VaultSnapshot, renames: RenameMap = .empty) {
        self.snapshot = snapshot
        self.renames = renames
    }

    public static let empty = SnapshotUpdate(snapshot: .empty)
}

/// What the UI is allowed to know about the store. Two implementations exist:
/// `InMemoryBackend` (here, reducer only — previews and tests) and `GTDServices.VaultBackend`
/// (the real vault). Features never see either type; they hold `AppModel`.
public protocol GTDBackend: Sendable {
    /// Emits on every local or remote change. The first element is the current update.
    func snapshots() -> AsyncStream<SnapshotUpdate>

    /// The state as of right now. Added by T00 so `AppModel.send` can update deterministically
    /// instead of racing the stream (ARCHITECTURE §4, contract change T00-2); it carries the
    /// renames of the last published update, so that path cannot lose them either.
    func currentUpdate() async -> SnapshotUpdate

    /// Runs one command. Throws `GTDError` for anything the UI must handle (cap, waiting info…).
    func perform(_ command: GTDCommand) async throws -> [AppPrompt]

    /// N6 — reverts the last filing/status change.
    func undo() async throws

    /// Human-readable label of what `undo()` would revert, or `nil` when there is nothing.
    func undoLabel() async -> String?
}

public extension GTDBackend {
    /// The snapshot as of right now, for callers that do not care about identity changes.
    func currentSnapshot() async -> VaultSnapshot {
        await currentUpdate().snapshot
    }
}
