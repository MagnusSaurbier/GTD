# GTDAppCore

The seam between the UI and whatever stores the data. Depends on `GTDModel` only.
No SwiftUI (only `Observation`), so it compiles and tests on Linux.

## Public API

- `GTDBackend` — `snapshots() -> AsyncStream<VaultSnapshot>`, `currentSnapshot()`,
  `perform(_:) -> [AppPrompt]`, `undo()`, `undoLabel()`.
- `AppModel` — `@MainActor @Observable`. `snapshot`, `undoLabel`, `prompt`, `lastError`,
  `today: () -> Day`; `send(_:) async throws`, `send(deriving:) async throws`,
  `perform(_:) async -> Bool`, `report(_:) async -> Bool`, `undo() async`, `start()`/`stop()`.
  Views get it with `@Environment(AppModel.self)`.
- `InMemoryBackend` — `actor`, reducer only, single-level undo by keeping the previous snapshot.
  `init(snapshot:)` plus `deviceID:`/`env:` for deterministic tests.

## Invariants

- **Commands run one at a time, in call order** (T40-2). `send(deriving:)` builds its command
  only when its turn comes, from the snapshot as it is then — that is what a caller writing a
  whole entity back (`FeatureOverview.ActionEditModel`'s autosave) must use, or it reverts the
  fields of a command that was still in flight when it built its payload. `undo()` queues too.
- `AppModel.send` refreshes `snapshot` and `undoLabel` **before returning**, both on success and
  on a thrown `GTDError`, so a caller can read them straight after `await`. That is why
  `GTDBackend` has `currentSnapshot()` (contract change T00-2).
- `GTDError` is rethrown for the UI to handle (cap sheet, waiting sheet). `undo()` never throws;
  a refused undo lands in `lastError`.
- **A refused command always reaches the person** (T41-1). A view either has a flow of its own
  for the error — and then uses `send` — or it uses `perform(_:)`/`report(_:)`, which put the
  error in `lastError` for the shell's one alert. `try? await model.send(…)` in a view is a bug:
  the person taps and nothing happens (STYLEGUIDE §1 "no lying UI"). A command that goes through
  clears `lastError`, exactly as `undo()` does.
- `snapshots()` is synchronous on purpose, so an actor backend must implement it `nonisolated`.
  `SnapshotHub` does the fan-out under an `NSLock` — the one justified `@unchecked Sendable`
  in this target. Its first element is always the current snapshot.
- `InMemoryBackend` does not make config edits, routine logs, review saves or archiving undoable
  (same rule as `GTDServices.UndoJournal`).

## Ownership

T00. `GTDServices.VaultBackend` (T16) is the second implementation of `GTDBackend` and must keep
the same observable behaviour — T16 has a parity test for it.

## Testing

`cd Packages/GTDKit && swift test --filter GTDAppCoreTests` — the T00 acceptance scenario
(file an inbox item to Next, hit the cap, complete a project action (prompt), undo), the T40-2
command-order tests, and `ErrorSurfacingTests` for `perform`/`report`.
