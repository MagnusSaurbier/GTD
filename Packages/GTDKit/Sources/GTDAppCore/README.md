# GTDAppCore

The seam between the UI and whatever stores the data. Depends on `GTDModel` only.
No SwiftUI (only `Observation`), so it compiles and tests on Linux.

## Public API

- `GTDBackend` — `snapshots() -> AsyncStream<SnapshotUpdate>`, `currentUpdate()`,
  `perform(_:) -> [AppPrompt]`, `undo()`, `undoLabel()`, `writeFailures()` (defaults to a
  stream that never yields — for a backend whose `perform` returns only once stored),
  `resolve(_:path:text:)` (writes the conflict sheet's merged note as-is; defaults to throwing
  `ConflictError.unsupported`); `currentSnapshot()` is an extension over `currentUpdate()`.
- `WriteConflict` — a refused stale write for the conflict sheet (N3, ARCHITECTURE §6
  2026-09-25): `basePath`/`base`, `path`/`mine` (this device), `theirsPath`/`theirs` (the vault
  now; a rename elsewhere is found by identical content), `theirsRenamed`/`mineRenamed`, and
  `suggestion: MergeSuggestion` (path + text + the number of hunks both sides changed).
  `ThreeWayMerge.merge(base:mine:theirs:)` is the line-based diff3 behind it: one side's
  change is taken, both sides' different change takes *theirs* and is counted. Rides on
  `WriteFailure.conflict`.
- `SnapshotUpdate` — one published state: the `VaultSnapshot` and the `RenameMap` of the command
  that produced it.
- `NavigationRemap` — `path(_:renames:exists:)` / `selection(_:renames:exists:)`: follow a
  rename, then drop what is gone. Both shells navigate by it.
- `AppModel` — `@MainActor @Observable`. `snapshot`, `renames`/`consumeRenames()`, `undoLabel`,
  `prompt`, `lastError`, `writeFailure`, `conflict` (a refusal that carries one lands here, not
  in `writeFailure`) with `resolveConflict(path:text:) async -> Bool` / `discardConflict()`,
  `today: () -> Day`; `send(_:) async throws`, `send(deriving:) async throws`,
  `perform(_:) async -> Bool`, `report(_:) async -> Bool`, `undo() async`, `start()`/`stop()`.
  Views get it with `@Environment(AppModel.self)`.
- `InMemoryBackend` — `actor`, reducer only, single-level undo by keeping the previous snapshot.
  `init(snapshot:)` plus `deviceID:`/`env:` for deterministic tests.
- `KeyBindings` (R-10, N7/I9) — the device-local, `Codable` table *command → key* behind the Mac
  keyboard: `KeyScreen` (the four screens that each refuse duplicates independently),
  `KeyCommand` (one case per rebindable single-key command, grouped by screen; `.defaultKey` is
  the I9/STYLEGUIDE §3.6/§3.10 factory map), `KeyStroke` (a displayable letter/digit/arrow, plus
  the four fixed tokens `.escape`/`.tab`/`.commandZ`/`.commandReturn` and the reserved
  `.digit`/`.shiftedDigit` action-card keys). `key(for:)` reads with fallback to the default;
  `rebind(_:to:)` throws `RebindError.fixed`/`.reserved`/`.duplicate(KeyCommand)`; `reset()` /
  `reset(_:)` restore defaults; `legend(for:titles:)`/`legendString(for:titles:)` build a Mac
  legend row from the current bindings and caller-supplied labels (no UI strings live here — this
  target has no `DesignSystem` dependency). Lives here rather than in `FeatureSettings` (which
  owns *persisting* one inside `DeviceSettings`) because `FeatureInbox.KeyMap` and
  `FeatureReview.ReviewSession` both resolve keys through it and neither may depend on the other's
  feature target or on `FeatureSettings` (ARCHITECTURE §2) — `GTDAppCore` is the one target all
  three already depend on.
- `MoveDestination` / `MovePlan` — drag-to-category (E3). `MovePlan.plan(action:to:snapshot:today:)`
  says what a row dropped on `.next`/`.someday`/`.waiting`/`.projects`/`.project(id)`/
  `.lists`/`.list(name)` needs: `.alreadyThere`, `.perform(command)` (nothing missing),
  `.card(status:missing:)` (the action card with those fields marked — `RequiredField.missing`
  with the action's `previous` status as it behaves today — a deferral that is back counts as
  Next, `Rules.effectiveStatus`, #86), `.pickProject`, `.pickList`;
  `accepts(…)` is the drop highlight. The
  reducer stays the authority; this only decides whether a dialogue is needed before sending.
- `ObsidianLink` — the one builder of "Open in Obsidian" URLs: `url(for: NoteID, vaultRoot:form:)`
  / `url(forVaultPath:vaultRoot:form:)`. Obsidian's `path=` must be an **absolute** path (a
  vault-relative one fails with "Vault not found"); a relative path goes in `file=` beside
  `vault=<vault folder name>`. `Form.platformDefault` is `.absolutePath` on macOS and
  `.vaultAndFile` elsewhere (the path an iOS bookmark resolves to is not known to be the one
  Obsidian's sandbox uses). Values are escaped down to RFC 3986 unreserved characters, so `&`,
  `#`, `+`, `=` in a file name survive. `nil` without a vault root — the views then show no link.
  `filePath(for:vaultRoot:)` / `filePath(forVaultPath:vaultRoot:)` is the same join unescaped, for
  the detail view's "Copy path" (a `/do <path>` prompt takes it). Here because three feature
  targets need it and may not depend on each other.

## Invariants

- **Commands run one at a time, in call order.** `send(deriving:)` builds its command
  only when its turn comes, from the snapshot as it is then — that is what a caller writing a
  whole entity back (`FeatureOverview.ActionEditModel`'s autosave) must use, or it reverts the
  fields of a command that was still in flight when it built its payload. `undo()` queues too.
- `AppModel.send` refreshes `snapshot` and `undoLabel` **before returning**, both on success and
  on a thrown `GTDError`, so a caller can read them straight after `await`. That is why
  `GTDBackend` has `currentSnapshot()`.
- **A rename is published with the snapshot it produced, never separately.** A note's id is its
  file name (A1), so a renamed note's old id is as absent from the new snapshot as a deleted
  one's; nothing downstream could tell the two apart on its own. Both paths to the UI — the
  stream and `currentUpdate()` — carry the same `SnapshotUpdate`, and `AppModel` accumulates the
  renames until the shell calls `consumeRenames()`, so no update can be seen without them and
  none is lost when two arrive between two looks. The shell then remaps before it prunes
  (`NavigationRemap`); doing it the other way round pops the detail of the note being renamed.
- `GTDError` is rethrown for the UI to handle (cap sheet, waiting sheet). `undo()` never throws;
  a refused undo lands in `lastError`.
- **A refused command always reaches the person.** A view either has a flow of its own
  for the error — and then uses `send` — or it uses `perform(_:)`/`report(_:)`, which put the
  error in `lastError` for the shell's one alert. `try? await model.send(…)` in a view is a bug:
  the person taps and nothing happens (STYLEGUIDE §1 "no lying UI"). A command that goes through
  clears `lastError`, exactly as `undo()` does.
- **A write refused after the fact is held until dismissed.** `VaultBackend` writes behind the
  UI; its `WriteFailure` lands in `writeFailure`, not `lastError`, because the next command that
  goes through clears `lastError` — and would do so before the person has read it. Only
  `clearError()` clears it. The snapshot has already been reverted by the backend.
- **Held edits.** An editor that keeps typed text back until blur/close conforms to
  `AppModel.HeldEdits` and calls `register(_:)` (held weakly). `flushHeldEdits()` is the shell's
  "the app is about to stop running" — it runs before the write queue is flushed. A holder also
  reports its `unsavedText` (typed title/body only) and calls `heldEditsChanged()`; the model
  forwards it to `unsavedJournal` (`UnsavedTextJournal`, #56), the crash-safe copy the shell
  hands every model. `restoreUnsaved` / `discardUnsaved` settle what an earlier run left.
- `snapshots()` is synchronous on purpose, so an actor backend must implement it `nonisolated`.
  `SnapshotHub` does the fan-out under an `NSLock` — the one justified `@unchecked Sendable`
  in this target. Its first element is always the current snapshot.
- `InMemoryBackend` does not make config edits, routine logs, review saves or archiving undoable
  (same rule as `GTDServices.UndoJournal`).

## Two backends, one behaviour

`GTDServices.VaultBackend` is the second implementation of `GTDBackend`, and the two must stay
observably identical: `GTDServicesTests/ParityTests` drives both through the same commands and
compares the result, and the undo rule and its labels have one definition each
(`Rules.isUndoable`, `UndoLabel`). `UndoLabel` is STYLEGUIDE §3.8/§6.3's wording verbatim,
including the list toasts: `Added to <list>` when a capture is filed into one, `Done` when an
item is checked off (and when a card is filed by the 2-minute rule, I4/D13), and
`Filed to Next`/`Filed to Someday` when one is made into an action.

## Testing

`cd Packages/GTDKit && swift test --filter GTDAppCoreTests` — 61 tests (`WriteFailureTests`: held until dismissed, wording). The acceptance scenario (file an
inbox item to Next, hit the cap, complete a project action (prompt), undo), the command-order
tests, `ErrorSurfacingTests` for `perform`/`report`, and `KeyBindingsTests` (defaults, rebind
happy path, duplicate-within-screen refusal naming the conflicting command, same key on a
different screen, fixed/reserved keys, reset, Codable round-trip incl. a missing/unknown command,
legends).
