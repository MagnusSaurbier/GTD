# GTDServices

The production backend: `Reducer.reduce` → `SnapshotDiff` → `VaultStore.commit` → undo journal.
Owned by T16. Foundation-only — every file here compiles and is tested on Linux.

## Public API

- `VaultBackend` (actor, conforms to `GTDAppCore.GTDBackend`) — `init(store:deviceID:)`, plus a
  full initialiser taking `journal`, `stateDirectory` and `env` for tests. `start()` / `stop()`
  bracket its lifetime; `perform`, `undo`, `undoLabel`, `snapshots`, `currentSnapshot` are the
  protocol. `lastHousekeepingError` says why the last automatic archive did not run.
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
   keep their modification date, which the staleness signals depend on. The diff short-circuits
   on entity equality first (T41): `encode` is a pure function of the entity, so an unchanged
   note costs a comparison instead of two encodes. Without it one command re-encoded the whole
   vault twice — 4.4 s on 1 000 notes.
4. **Undo is refused, never forced.** Each entry stores a content hash per file it would touch;
   anything that moved in the meantime (sync, Obsidian, another device) turns the undo into
   `ServiceError.undoStale`. The journal is deeper than N6 asks (20), so ⌘Z walks back a session.
5. **Optimistic then authoritative.** A successful command publishes the reduced snapshot at
   once; the store's scanned snapshot replaces it when it arrives. `pullFromStore` always asks
   the store for its *current* value, so a late event can never walk the app backwards.
6. The archive and the trash pick a free name on collision (they are app-owned); anywhere else a
   taken destination is `GTDError.titleCollision` for the user to resolve.
7. Housekeeping (`start()`): folder skeleton from `VaultLayout`, then `archiveCompleted` once per
   day, remembered in `housekeeping.json` next to the journal — never in the vault. The day is
   recorded **only on success**, so a failed archive is retried at the next launch rather than
   skipped until tomorrow; the reason is on `lastHousekeepingError`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDServicesTests`. `ParityTests` drives 21
commands through `InMemoryBackend` and `VaultBackend` and compares a fresh scan of the vault with
the in-memory snapshot after every step; `SnapshotShape` says which fields are compared and why.
`SyncScenarioTests` (T41) runs the situations that need two writers on one folder — two devices
logging the same routine, an undo refused after someone else wrote, a conflict copy, an evicted
file, and a rename while another view holds the old `NoteID`. `PerformanceTests` (T41) generates
a vault of any size (`GTD_BENCH_NOTES`, driven by `scripts/benchmark.sh`) and asserts the *shape*
of the work rather than the clock: one changed note is one write and one decode, whatever the
size of the vault.
