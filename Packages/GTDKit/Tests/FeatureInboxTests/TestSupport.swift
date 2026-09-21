import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// A backend the tests fully control: `InMemoryBackend` semantics (reducer + single-level undo)
/// plus `capture(_:)`, so a card arriving mid-session can be simulated (I7).
///
/// `@unchecked Sendable` is sound: every access goes through the synchronous helpers below, which
/// hold `lock`. (`NSLock` may not be taken in an `async` function, hence the split.)
final class TestBackend: GTDBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: VaultSnapshot
    private var undoState: VaultSnapshot?
    private var label: String?
    private var renames: RenameMap = .empty
    private var continuations: [UUID: AsyncStream<SnapshotUpdate>.Continuation] = [:]
    private let env: ReducerEnv

    init(snapshot: VaultSnapshot, env: ReducerEnv = Fixtures.reducerEnv(deviceID: "test")) {
        self.snapshot = snapshot
        self.env = env
    }

    // MARK: GTDBackend

    func snapshots() -> AsyncStream<SnapshotUpdate> {
        AsyncStream { continuation in
            let current = subscribe(continuation)
            continuation.yield(SnapshotUpdate(snapshot: current))
        }
    }

    func currentUpdate() async -> SnapshotUpdate { SnapshotUpdate(snapshot: read(), renames: readRenames()) }

    func perform(_ command: GTDCommand) async throws -> [AppPrompt] { try apply(command) }

    func undo() async throws { try revert() }

    func undoLabel() async -> String? { readLabel() }

    /// A new capture lands in the vault while the session is running (C1, I7).
    func capture(_ item: InboxItem) {
        mutate { $0.inbox.append(item) }
    }

    // MARK: Synchronous internals (the only place the lock is taken)

    private func subscribe(_ continuation: AsyncStream<SnapshotUpdate>.Continuation) -> VaultSnapshot {
        let id = UUID()
        lock.lock()
        continuations[id] = continuation
        let current = snapshot
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.continuations[id] = nil
            self.lock.unlock()
        }
        return current
    }

    private func read() -> VaultSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    private func readRenames() -> RenameMap {
        lock.lock()
        defer { lock.unlock() }
        return renames
    }

    private func readLabel() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return label
    }

    private func apply(_ command: GTDCommand) throws -> [AppPrompt] {
        lock.lock()
        let previous = snapshot
        let reduction: Reduction
        do {
            reduction = try Reducer.reduce(snapshot, command, env: env)
        } catch {
            lock.unlock()
            throw error
        }
        snapshot = reduction.snapshot
        undoState = previous
        label = "Last change"
        renames = reduction.renames
        let published = SnapshotUpdate(snapshot: snapshot, renames: reduction.renames)
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(published) }
        return reduction.prompts
    }

    private func revert() throws {
        lock.lock()
        guard let undoState else {
            lock.unlock()
            throw GTDError.invalid("Nothing to undo")
        }
        snapshot = undoState
        self.undoState = nil
        label = nil
        renames = .empty
        let published = SnapshotUpdate(snapshot: snapshot)
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(published) }
    }

    private func mutate(_ change: (inout VaultSnapshot) -> Void) {
        lock.lock()
        change(&snapshot)
        renames = .empty
        let published = SnapshotUpdate(snapshot: snapshot)
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(published) }
    }
}

enum InboxTestSupport {

    /// A session over the sample vault, with a device-local store that never touches
    /// `UserDefaults` and a fixed clock.
    @MainActor
    static func makeSession(
        snapshot: VaultSnapshot = Fixtures.sampleSnapshot,
        lastKnowledgeFolder: String? = nil,
        defaults: (any InboxDefaultsStore)? = nil,
        bindings: KeyBindings = .defaults,
        platform: NavbarPlatform = .iPhone
    ) -> (session: InboxSession, model: AppModel, backend: TestBackend) {
        let backend = TestBackend(snapshot: snapshot)
        let model = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        let session = InboxSession(
            model: model,
            defaults: defaults ?? EphemeralInboxDefaults(lastKnowledgeFolder: lastKnowledgeFolder),
            bindings: bindings,
            platform: platform,
            now: { Fixtures.date(Fixtures.today, 10, 0) })
        return (session, model, backend)
    }

    /// Most tests are about what the *opened* action card does, so they start one step in.
    @MainActor
    static func openedActionCard(
        snapshot: VaultSnapshot = Fixtures.sampleSnapshot,
        defaults: (any InboxDefaultsStore)? = nil
    ) async -> (session: InboxSession, model: AppModel, backend: TestBackend) {
        let made = makeSession(snapshot: snapshot, defaults: defaults)
        await made.session.take(.openAction)
        return made
    }

    /// Waits for the snapshot stream to reach the model (bounded, so a wrong expectation fails
    /// the test instead of hanging).
    @MainActor
    static func wait(for condition: @MainActor () -> Bool, limit: Int = 500) async {
        for _ in 0..<limit {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    static func capture(_ text: String, at stamp: String) -> InboxItem {
        InboxItem(
            id: NoteID(path: "Inbox/\(stamp).md"),
            text: text,
            created: Fixtures.date(Fixtures.today, 12, 0))
    }
}
