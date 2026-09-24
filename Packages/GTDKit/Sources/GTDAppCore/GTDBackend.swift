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

/// A change the person already saw happen that the store then could not save.
///
/// A backend that writes behind the UI (`GTDServices.VaultBackend`) reverts the snapshot to what
/// the store really holds and reports one of these. `discarded` counts the later changes that
/// were queued behind the refused one and went with it — they were built on top of it.
public struct WriteFailure: Error, Sendable, CustomStringConvertible {
    /// `UndoLabel` of the command whose write was refused — the words the person saw in the toast.
    public var label: String
    public var reason: any Error
    public var discarded: Int
    /// Set when the refusal is the stale-write guard's (N3): both versions of the note and a
    /// proposed merge, for the conflict sheet. `AppModel` shows the sheet instead of the alert.
    public var conflict: WriteConflict?

    public init(label: String, reason: any Error, discarded: Int = 0, conflict: WriteConflict? = nil) {
        self.label = label
        self.reason = reason
        self.discarded = discarded
        self.conflict = conflict
    }

    public var description: String {
        var text = "\u{201C}\(label)\u{201D} could not be saved to the vault and was reverted. \(reason)"
        if discarded == 1 { text += " One later change was reverted with it." }
        if discarded > 1 { text += " \(discarded) later changes were reverted with it." }
        return text
    }
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

    /// Writes that were refused **after** `perform` returned. A backend whose `perform` only
    /// returns once the change is stored never yields (the default).
    func writeFailures() -> AsyncStream<WriteFailure>

    /// Runs one command. Throws `GTDError` for anything the UI must handle (cap, waiting info…).
    func perform(_ command: GTDCommand) async throws -> [AppPrompt]

    /// N6 — reverts the last filing/status change.
    func undo() async throws

    /// Human-readable label of what `undo()` would revert, or `nil` when there is nothing.
    func undoLabel() async -> String?

    /// Writes the note the person merged in the conflict sheet — `text` as-is at `path`,
    /// moving the vault's copy there first when the title changed — and makes it undoable.
    /// The one write besides `undo()` that bypasses the reducer (ARCHITECTURE §6, 2026-09-25).
    func resolve(_ conflict: WriteConflict, path: String, text: String) async throws
}

public extension GTDBackend {
    func writeFailures() -> AsyncStream<WriteFailure> {
        AsyncStream { $0.finish() }
    }

    /// A backend without files has nothing to merge into.
    func resolve(_ conflict: WriteConflict, path: String, text: String) async throws {
        throw ConflictError.unsupported
    }

    /// The snapshot as of right now, for callers that do not care about identity changes.
    func currentSnapshot() async -> VaultSnapshot {
        await currentUpdate().snapshot
    }
}
