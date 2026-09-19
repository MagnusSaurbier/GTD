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
    /// Tail of the serial command chain — see `send(deriving:)`.
    private var tail: Task<Void, Never>?

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
        try await send(deriving: { command })
    }

    /// Runs a command that is **built at the moment it starts**, from the snapshot as it is
    /// then. Returning `nil` from `make` cancels the command.
    ///
    /// Commands are serialised: at most one is in flight, in call order (T40-2). A caller that
    /// derives its command from `snapshot` — the autosaving action editor writing a whole
    /// `Action` back — must use this overload, because a command built before another one that
    /// is already in flight lands is built on state that command has already superseded, and
    /// writing it would silently revert the other's fields.
    public func send(deriving make: @MainActor @escaping () -> GTDCommand?) async throws {
        let previous = tail
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let command = make() else { return }
            try await self.run(command)
        }
        tail = Task { @MainActor in _ = try? await work.value }
        try await work.value
    }

    /// The command itself, once it is this command's turn.
    private func run(_ command: GTDCommand) async throws {
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

    /// Runs a command whose refusal the caller has nothing better to do with than **show**.
    ///
    /// Anything thrown lands in `lastError`, which the app shell surfaces in its one alert
    /// (T40) — the honest replacement for `try? await send(…)` at a call site that has no
    /// flow of its own for the error. A command the person asked for that silently does
    /// nothing is a lying UI (STYLEGUIDE §1), so a view either handles the error itself
    /// (the cap sheet, the waiting sheet) or sends it through here. Returns `false` when the
    /// command was refused (T41).
    @discardableResult
    public func perform(_ command: GTDCommand) async -> Bool {
        await report { try await self.send(command) }
    }

    /// `perform` for work that is a few commands, or a feature model's own method: the same
    /// "a refusal must reach the person" rule, one level up.
    @discardableResult
    public func report(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            lastError = nil
            return true
        } catch {
            lastError = error
            return false
        }
    }

    /// N6. Never throws — a refused undo (T16: the file changed remotely) lands in `lastError`.
    /// Queued behind any command still in flight, like `send`.
    public func undo() async {
        let previous = tail
        let work = Task { @MainActor [weak self] in
            await previous?.value
            await self?.runUndo()
        }
        tail = work
        await work.value
    }

    private func runUndo() async {
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
