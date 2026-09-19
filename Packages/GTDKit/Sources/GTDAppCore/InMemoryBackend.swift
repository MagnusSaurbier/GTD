import Foundation
import GTDModel

/// Reducer-only backend: no files, single-level undo by keeping the previous snapshot.
/// Used by SwiftUI previews, feature tests and the app's `-useFixtures` mode.
public actor InMemoryBackend: GTDBackend {
    private var snapshot: VaultSnapshot
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
        self.env = env ?? { ReducerEnv.live(deviceID: deviceID) }
        self.hub = SnapshotHub(initial: snapshot)
    }

    nonisolated public func snapshots() -> AsyncStream<VaultSnapshot> { hub.stream() }

    public func currentSnapshot() -> VaultSnapshot { snapshot }

    public func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        let previous = snapshot
        let reduction = try Reducer.reduce(snapshot, command, env: env())
        snapshot = reduction.snapshot
        if Rules.isUndoable(command) {
            undoState = (previous, UndoLabel.of(command, in: previous))
        }
        hub.publish(snapshot)
        return reduction.prompts
    }

    public func undo() async throws {
        guard let undoState else { throw GTDError.invalid("Nothing to undo") }
        snapshot = undoState.snapshot
        self.undoState = nil
        hub.publish(snapshot)
    }

    public func undoLabel() async -> String? { undoState?.label }
}

/// Fans a snapshot out to every `snapshots()` consumer. Lives outside the actor because
/// `GTDBackend.snapshots()` is synchronous, so it must be callable from any isolation domain.
/// `@unchecked Sendable` is sound here: every access is under `lock`.
final class SnapshotHub: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: VaultSnapshot
    private var continuations: [UUID: AsyncStream<VaultSnapshot>.Continuation] = [:]

    init(initial: VaultSnapshot) {
        latest = initial
    }

    func stream() -> AsyncStream<VaultSnapshot> {
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

    func publish(_ snapshot: VaultSnapshot) {
        lock.lock()
        latest = snapshot
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(snapshot) }
    }
}
