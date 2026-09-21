import Foundation
import GTDModel

/// Reducer-only backend: no files, single-level undo by keeping the previous snapshot.
/// Used by SwiftUI previews, feature tests and the app's `-useFixtures` mode.
public actor InMemoryBackend: GTDBackend {
    private var snapshot: VaultSnapshot
    /// What was published last — the snapshot plus the renames that produced it, so the stream
    /// and `currentUpdate()` hand out the same value (`SnapshotUpdate`).
    private var latest: SnapshotUpdate
    private var undoState: (snapshot: VaultSnapshot, label: String)?
    private let env: @Sendable () -> ReducerEnv
    private let hub: SnapshotHub

    /// `InMemoryBackend(snapshot:)` is the contract initialiser; `deviceID` and `env` are
    /// additions for deterministic tests (fix `now`/`today` by supplying `env`).
    public init(
        snapshot: VaultSnapshot,
        deviceID: String = "preview",
        env: (@Sendable () -> ReducerEnv)? = nil
    ) {
        self.snapshot = snapshot
        self.latest = SnapshotUpdate(snapshot: snapshot)
        self.env = env ?? { ReducerEnv.live(deviceID: deviceID) }
        self.hub = SnapshotHub(initial: SnapshotUpdate(snapshot: snapshot))
    }

    nonisolated public func snapshots() -> AsyncStream<SnapshotUpdate> { hub.stream() }

    public func currentUpdate() -> SnapshotUpdate { latest }

    public func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        let previous = snapshot
        let reduction = try Reducer.reduce(snapshot, command, env: env())
        snapshot = reduction.snapshot
        if Rules.isUndoable(command) {
            undoState = (previous, UndoLabel.of(command, in: previous))
        }
        publish(SnapshotUpdate(snapshot: snapshot, renames: reduction.renames))
        return reduction.prompts
    }

    public func undo() async throws {
        guard let undoState else { throw GTDError.invalid("Nothing to undo") }
        snapshot = undoState.snapshot
        self.undoState = nil
        publish(SnapshotUpdate(snapshot: snapshot))
    }

    public func undoLabel() async -> String? { undoState?.label }

    private func publish(_ update: SnapshotUpdate) {
        latest = update
        hub.publish(update)
    }
}

/// Fans an update out to every `snapshots()` consumer. Lives outside the actor because
/// `GTDBackend.snapshots()` is synchronous, so it must be callable from any isolation domain.
/// `@unchecked Sendable` is sound here: every access is under `lock`.
final class SnapshotHub: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: SnapshotUpdate
    private var continuations: [UUID: AsyncStream<SnapshotUpdate>.Continuation] = [:]

    init(initial: SnapshotUpdate) {
        latest = initial
    }

    func stream() -> AsyncStream<SnapshotUpdate> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            let current = self.latest
            self.lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    func publish(_ update: SnapshotUpdate) {
        lock.lock()
        latest = update
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(update) }
    }
}
