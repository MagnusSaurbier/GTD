# GTDServices

The production backend: `Reducer.reduce` → `SnapshotDiff` → `VaultStore.commit` → undo journal.
Owned by T16. Foundation-only — every file here compiles and is tested on Linux.

## Public API

- `VaultBackend` (actor, conforms to `GTDAppCore.GTDBackend`) — `init(store:deviceID:)`, plus a
  full initialiser taking `journal`, `stateDirectory` and `env` for tests. `start()` / `stop()`
  bracket its lifetime; `perform`, `undo`, `undoLabel`, `snapshots`, `currentSnapshot` are the
  protocol.
- `SnapshotDiff.ops(from:to:extraOps:timeZone:)` — two snapshots and the reducer's `extraOps`
  into one ordered list of `VaultFileOp`.
- `UndoJournal` (actor) — device-local, persisted in Application Support, keeps 20 entries.
- `ServiceError` — `.nothingToUndo`, `.undoStale(path:)`.

## Invariants

1. **One command, one transaction.** `extraOps` (trash, archive, knowledge and rename moves) and
   the content writes go into a single `commit`, so a rename and the project steps that link to
   the renamed note can never come apart. A refusal writes nothing at all.
2. **`extraOps` owns every path it names** (ARCHITECTURE §4, T00-1). A removed entity nobody
   claimed is trashed; a move destination that turns up as a new entity is a rename.
3. **A file is written only when its encoding changed.** `NoteCodec` patches the text it kept in
   `NotePassthrough`, so "the encoding changed" means "the file would change" — untouched notes
   keep their modification date, which the staleness signals depend on.
4. **Undo is refused, never forced.** Each entry stores a content hash per file it would touch;
   anything that moved in the meantime (sync, Obsidian, another device) turns the undo into
   `ServiceError.undoStale`. The journal is deeper than N6 asks (20), so ⌘Z walks back a session.
5. **Optimistic then authoritative.** A successful command publishes the reduced snapshot at
   once; the store's scanned snapshot replaces it when it arrives. `pullFromStore` always asks
   the store for its *current* value, so a late event can never walk the app backwards.
6. The archive and the trash pick a free name on collision (they are app-owned); anywhere else a
   taken destination is `GTDError.titleCollision` for the user to resolve.
7. Housekeeping (`start()`): folder skeleton from `VaultLayout`, then `archiveCompleted` once per
   day, remembered in `housekeeping.json` next to the journal — never in the vault.

## Testing

`cd Packages/GTDKit && swift test --filter GTDServicesTests` (40 tests). `ParityTests` drives 21
commands through `InMemoryBackend` and `VaultBackend` and compares a fresh scan of the vault with
the in-memory snapshot after every step; `SnapshotShape` says which fields are compared and why.
