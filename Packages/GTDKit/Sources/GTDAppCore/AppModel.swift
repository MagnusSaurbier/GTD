import Foundation
import Observation
import GTDModel

/// The one object every view reads. Views get it via `@Environment(AppModel.self)`.
///
/// It owns no GTD semantics — it forwards commands to the backend and republishes the snapshot.
@MainActor
@Observable
public final class AppModel {
    public private(set) var snapshot: VaultSnapshot
    public private(set) var undoLabel: String?
    /// Presented by the app shell (T40), never by a feature view.
    public var prompt: AppPrompt?
    /// Last error that had nowhere else to go (a failed `undo()`). The shell may surface it.
    public private(set) var lastError: (any Error)?
    /// Injectable clock so previews and tests are deterministic.
    public let today: () -> Day

    private let backend: any GTDBackend
    private var observation: Task<Void, Never>?

    public init(backend: any GTDBackend, today: @escaping () -> Day = Day.today) {
        self.backend = backend
        self.today = today
        self.snapshot = .empty
        start()
    }

    /// Seeds the snapshot synchronously — for previews, which must render on the first frame.
    public convenience init(
        backend: any GTDBackend,
        snapshot: VaultSnapshot,
        today: @escaping () -> Day = Day.today
    ) {
        self.init(backend: backend, today: today)
        self.snapshot = snapshot
    }

    /// Subscribes to the backend. Called from `init`; safe to call again after `stop()`.
    public func start() {
        guard observation == nil else { return }
        let backend = self.backend
        observation = Task { [weak self] in
            for await snapshot in backend.snapshots() {
                guard let self else { return }
                self.apply(snapshot)
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    private func apply(_ snapshot: VaultSnapshot) {
        self.snapshot = snapshot
    }

    /// Runs a command. `GTDError` is rethrown so the UI can react (cap sheet, waiting sheet);
    /// the snapshot and undo label are refreshed before returning, so callers can read them
    /// immediately after `await`.
    public func send(_ command: GTDCommand) async throws {
        do {
            let prompts = try await backend.perform(command)
            snapshot = await backend.currentSnapshot()
            undoLabel = await backend.undoLabel()
            if let first = prompts.first { prompt = first }
        } catch {
            // Keep the UI's view of the world truthful even when the command failed.
            snapshot = await backend.currentSnapshot()
            undoLabel = await backend.undoLabel()
            throw error
        }
    }

    /// N6. Never throws — a refused undo (T16: the file changed remotely) lands in `lastError`.
    public func undo() async {
        do {
            try await backend.undo()
            lastError = nil
        } catch {
            lastError = error
        }
        snapshot = await backend.currentSnapshot()
        undoLabel = await backend.undoLabel()
    }

    public func clearError() { lastError = nil }
}
