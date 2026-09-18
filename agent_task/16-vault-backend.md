# T16 — Vault backend & undo (`GTDServices`)

**Wave 2 · needs T10, T11, T15**

## Goal

The production `GTDBackend`: commands go through the reducer and come out as file transactions.

## Requirements covered

N3, N4, N6, A5, and end-to-end correctness of every command.

## Owns

`Sources/GTDServices/`, `Tests/GTDServicesTests/`.

## Deliverables

- `VaultBackend: GTDBackend` (actor):
  1. take current snapshot, run `Reducer.reduce`;
  2. `SnapshotDiff`: compare old/new entity collections by `NoteID` → changed/added entities are
     encoded with `NoteCodec` into `.put`; removed ones become `.move`/`.delete`; id changes
     (rename/move) become `.move`; append `extraOps`;
  3. `VaultStore.commit` → inverse ops go to the `UndoJournal`;
  4. return prompts; the new snapshot arrives through `snapshots()` (optimistically emit the
     reduced snapshot immediately so the UI never waits on the file watcher).
- `UndoJournal`: device-local, persisted, depth 1 is required (N6), keep 20. Entry = label +
  inverse ops + content hashes of the files it would overwrite; undo refuses (with a clear error)
  if a touched file changed remotely since.
  Undoable: inbox filing, status changes, completion, promotion. Not undoable: config edits, routine logs.
- Human-readable undo labels ("Filed 'Call bank' to Next").
- Housekeeping: run `archiveCompleted` once per launch/day; ensure folder skeleton from `VaultLayout` exists.
- Wikilink upkeep: when an action/project file is renamed or moved by the app, update `project:`
  links in affected actions and `→ [[…]]` in project steps within the same transaction.

## Acceptance

- Scenario tests on a temp copy of the sample vault, asserting on **file contents**: full inbox
  processing of all 5 decisions, cap error leaves files untouched, complete project action updates
  both files, undo restores byte-identical state, undo refused after external modification,
  archive moves, rename keeps links intact.
- Behavioural parity test: the same command script against `InMemoryBackend` and `VaultBackend` yields equal snapshots.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
