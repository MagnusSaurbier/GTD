import Foundation
import GTDModel
import GTDMarkdown
import GTDVault

/// `Reducer.reduce` → diff old/new snapshot → encode changed entities → `VaultStore.commit`
/// → push the inverse ops onto the undo journal. **Owned by T16.**
///
/// It deliberately does *not* conform to `GTDAppCore.GTDBackend` here: `GTDServices` must not
/// depend on `GTDAppCore` (ARCHITECTURE §2). T16 adds the conformance in this target by
/// importing `GTDAppCore`, which is allowed — the forbidden direction is Feature → GTDServices.
public actor VaultBackend {
    private let store: any VaultStore
    private let deviceID: String

    public init(store: any VaultStore, deviceID: String) {
        self.store = store
        self.deviceID = deviceID
    }

    nonisolated public func snapshots() -> AsyncStream<VaultSnapshot> { store.snapshots() }

    public func currentSnapshot() -> VaultSnapshot { .empty }   // T16

    public func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        throw ServiceError.notImplemented("T16: VaultBackend.perform")
    }

    public func undo() async throws {
        throw ServiceError.notImplemented("T16: VaultBackend.undo")
    }

    public func undoLabel() async -> String? { nil }
}

/// Diffs two snapshots into file operations. **Owned by T16.**
///
/// Rule shared with `Reducer` (see its doc comment): a path already named in `Reduction.extraOps`
/// is owned by `extraOps`; the diff must not emit another operation for it.
public enum SnapshotDiff {
    public static func ops(
        from old: VaultSnapshot,
        to new: VaultSnapshot,
        extraOps: [VaultFileOp]
    ) throws -> [VaultFileOp] {
        throw ServiceError.notImplemented("T16: SnapshotDiff.ops")
    }
}

/// Device-local, persisted, depth ≥ 1 (N6), keeps 20. **Owned by T16.**
public actor UndoJournal {
    public init() {}

    public struct Entry: Sendable, Equatable {
        public var label: String
        public var inverseOps: [VaultFileOp]
        /// Content hashes of the files the undo would overwrite; undo is refused when they moved.
        public var hashes: [String: String]

        public init(label: String, inverseOps: [VaultFileOp], hashes: [String: String]) {
            self.label = label
            self.inverseOps = inverseOps
            self.hashes = hashes
        }
    }

    public func push(_ entry: Entry) {}
    public func peek() -> Entry? { nil }
    public func pop() -> Entry? { nil }
}

public enum ServiceError: Error, Equatable {
    case notImplemented(String)
    /// The undo would overwrite a file that changed remotely since (N3, T16).
    case undoStale(path: String)
}
