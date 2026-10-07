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
    /// Notes whose `NoteID` changed since the shell last consumed this — see `consumeRenames()`.
    ///
    /// Written in the same main-actor step as `snapshot`, and always before it, so an observer
    /// of `snapshot` reading this in the same change sees the renames that produced it.
    public private(set) var renames: RenameMap = .empty
    public private(set) var undoLabel: String?
    /// Presented by the app shell (T40), never by a feature view.
    public var prompt: AppPrompt?
    /// Last error that had nowhere else to go (a failed `undo()`). The shell may surface it.
    public private(set) var lastError: (any Error)?
    /// A change that was shown and then could not be saved (`WriteFailure`); the snapshot has
    /// already gone back to what the vault holds. Kept apart from `lastError` because the next
    /// command that goes through clears that one — and with writes queued behind the UI, the
    /// next command is usually through before the person has read this. Only `clearError()`
    /// clears it.
    public private(set) var writeFailure: WriteFailure?
    /// A refused write that the person can settle: both versions of the note and a proposed
    /// merge (N3). The shell opens the conflict sheet on it; `resolveConflict` / `discardConflict`
    /// close it. A refusal that carries one never lands in `writeFailure`.
    public private(set) var conflict: WriteConflict?
    /// Injectable clock so previews and tests are deterministic.
    public let today: () -> Day

    private let backend: any GTDBackend
    private var observation: Task<Void, Never>?
    private var failureObservation: Task<Void, Never>?
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
            for await update in backend.snapshots() {
                guard let self else { return }
                self.apply(update)
            }
        }
        failureObservation = Task { [weak self] in
            for await failure in backend.writeFailures() {
                guard let self else { return }
                // The first one stays: it is the one the person has to read, and a second
                // refusal while the alert is up is almost always the same cause.
                if let conflict = failure.conflict {
                    if self.conflict == nil { self.conflict = conflict }
                } else if self.writeFailure == nil {
                    self.writeFailure = failure
                }
                self.undoLabel = await backend.undoLabel()
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        failureObservation?.cancel()
        failureObservation = nil
    }

    /// The one way a published state reaches the UI. Renames **accumulate** until the shell
    /// takes them: two updates that arrive before it looks (or the same one arriving twice, once
    /// through the stream and once through `currentUpdate()`) compose into one map rather than
    /// the earlier one being lost.
    private func apply(_ update: SnapshotUpdate) {
        renames = renames.merging(update.renames)
        snapshot = update.snapshot
    }

    /// Takes the renames published since the last call, leaving none behind.
    ///
    /// The app shell calls this when it reacts to a snapshot change, and is the only caller:
    /// it remaps its navigation with them before pruning the notes that really are gone
    /// (`NavigationRemap`).
    public func consumeRenames() -> RenameMap {
        defer { renames = .empty }
        return renames
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
            apply(await backend.currentUpdate())
            undoLabel = await backend.undoLabel()
            if let first = prompts.first { prompt = first }
        } catch {
            // Keep the UI's view of the world truthful even when the command failed.
            apply(await backend.currentUpdate())
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

    /// R-5 — drops favourites whose list folder is gone (`GTDCommand.pruneFavouriteLists`). Run
    /// at launch and as the inbox opens its Knowledge / List card; writes only when a favourite
    /// is actually stale. Reduced on the backend's snapshot, so it is safe before this model has
    /// received its first one. A refusal reaches the alert, but unlike `perform` a success does
    /// not clear an error the person has not read yet — nobody asked for this command.
    public func pruneFavouriteLists() async {
        do {
            try await send(.pruneFavouriteLists)
        } catch {
            lastError = error
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
        apply(await backend.currentUpdate())
        undoLabel = await backend.undoLabel()
    }

    // MARK: - Held edits

    /// Something that holds typed text back from the vault until a natural moment (the editors:
    /// blur, close) and can be told that such a moment is now.
    public protocol HeldEdits: AnyObject {
        @MainActor func flush() async
        /// The typed text not yet in the vault, for the crash journal (#56); `nil` when none.
        /// A holder calls `heldEditsChanged()` whenever this may have changed.
        @MainActor var unsavedText: UnsavedText? { get }
    }

    private struct WeakHolder { weak var value: (any HeldEdits)? }
    private var holders: [ObjectIdentifier: WeakHolder] = [:]

    /// The crash-safe copy of held edits (#56). The shell hands its one journal to every model
    /// it creates; `nil` (tests, previews) keeps no copy.
    public var unsavedJournal: UnsavedTextJournal?

    /// #94 — what open dialogs hold that has no place in the vault yet (`InputDrafts`). The
    /// shell hands its one file-backed store to every model it creates; the default keeps
    /// drafts in memory for this run only (tests, previews).
    @ObservationIgnored public var inputDrafts = InputDrafts()

    /// Editors register themselves; they are held weakly and forgotten once they are gone.
    public func register(_ holder: any HeldEdits) {
        holders = holders.filter { $0.value.value != nil }
        holders[ObjectIdentifier(holder)] = WeakHolder(value: holder)
    }

    /// A holder's unsaved text changed (typed, saved, refused): the journal follows shortly.
    public func heldEditsChanged() {
        unsavedJournal?.update(live: holders.values.compactMap { $0.value?.unsavedText })
    }

    /// Sends every held edit now. The shell calls it when the app is about to stop running —
    /// backgrounding on iOS, ⌘Q on the Mac — before it waits for the write queue. The journal
    /// is brought up to date at once, so a clean quit leaves no "unsaved text" behind.
    public func flushHeldEdits() async {
        for holder in holders.values.compactMap(\.value) { await holder.flush() }
        heldEditsChanged()
        unsavedJournal?.writeNow()
        inputDrafts.writeNow()
    }

    /// #56 — writes text an earlier run never saved back into its note. `false` when the note
    /// is gone (nothing to write into; the sheet offers copying instead) or the write was
    /// refused (in `lastError`, and the entry stays in the journal).
    @discardableResult
    public func restoreUnsaved(_ entry: UnsavedText) async -> Bool {
        guard let command = entry.restoreCommand(in: snapshot) else { return false }
        let done = await perform(command)
        if done { unsavedJournal?.resolve(entry) }
        return done
    }

    /// #56 — the person let an earlier run's unsaved text go.
    public func discardUnsaved(_ entry: UnsavedText) {
        unsavedJournal?.resolve(entry)
    }

    public func clearError() {
        lastError = nil
        writeFailure = nil
    }

    /// Done in the conflict sheet: writes the merged note. A failure stays in `lastError` and
    /// the sheet stays open, so nothing the person typed is lost.
    @discardableResult
    public func resolveConflict(path: String, text: String) async -> Bool {
        guard let conflict else { return false }
        let done = await report { try await self.backend.resolve(conflict, path: path, text: text) }
        if done {
            self.conflict = nil
            apply(await backend.currentUpdate())
            undoLabel = await backend.undoLabel()
        }
        return done
    }

    /// The sheet's other exit: the vault's version stands (the refused write was already
    /// reverted when the conflict was reported).
    public func discardConflict() {
        conflict = nil
    }
}
