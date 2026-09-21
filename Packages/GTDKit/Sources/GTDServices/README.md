# GTDServices

The production backend: `Reducer.reduce` → `SnapshotDiff` → publish → (queued) `VaultStore.commit` → undo journal.
Foundation-only — every file here compiles and is tested on Linux.

## Public API

- `VaultBackend` (actor, conforms to `GTDAppCore.GTDBackend`) — `init(store:deviceID:)`, plus a
  full initialiser taking `journal`, `stateDirectory` and `env` for tests. `start()` / `stop()`
  bracket its lifetime; `perform`, `undo`, `undoLabel`, `snapshots`, `currentSnapshot` are the
  protocol, plus `writeFailures()` and `flush()`; `writes: WritePolicy` (`.queued` by default,
  `.awaited` for tests that read files straight after a command). `lastHousekeepingError` says why the last automatic archive did not run.
- `SnapshotDiff.ops(from:to:extraOps:filedNotes:timeZone:)` — two snapshots, the reducer's
  `extraOps` and its `filedNotes`
  into one ordered list of `VaultFileOp`. A `.moveFolder` in `extraOps` owns *both* ends of the
  tree it moves: no note under the old path is trashed for "leaving the snapshot", and a note
  under the new path is the same note, written again only if its content changed too.
  A `.createFolder` owns no path at all — an empty folder holds no note (§5a).
  `Reduction.filedNotes` is the Knowledge note an inbox filing writes (I4b): it lives in no
  snapshot collection, so the reducer says what it says and **this** target encodes it — the same
  division as the weekly review note, because `GTDModel` never produces markdown. Its body
  replaces whatever the file holds (never a stale copy of the capture), its own text rides along
  so unknown frontmatter survives, and the put comes after the move that put the file there.
- `UndoJournal` (actor) — device-local, persisted in Application Support, keeps 20 entries.
- `ServiceError` — `.nothingToUndo`, `.undoStale(path:)`, `.writeDiscarded`.

## Invariants

1. **One command, one transaction.** `extraOps` (trash, archive, knowledge and rename moves) and
   the content writes go into a single `commit`, so a rename and the project steps that link to
   the renamed note can never come apart. A refusal writes nothing at all.
2. **`extraOps` owns every path it names** (ARCHITECTURE §4). A removed entity nobody
   claimed is trashed; a move destination that turns up as a new entity is a rename.
3. **A file is written only when its encoding changed.** `NoteCodec` patches the text it kept in
   `NotePassthrough`, so "the encoding changed" means "the file would change" — untouched notes
   keep their modification date, which the staleness signals depend on. The diff short-circuits
   on entity equality first: `encode` is a pure function of the entity, so an unchanged
   note costs a comparison instead of two encodes. Without it one command re-encoded the whole
   vault twice — 4.4 s on 1 000 notes.
4. **Undo is refused, never forced.** Each entry stores a content hash per file it would touch;
   anything that moved in the meantime (sync, Obsidian, another device) turns the undo into
   `ServiceError.undoStale`. For a `.moveFolder` that means the files **inside** the folder:
   they are the ones the undo carries back, so the journal asks the store for
   `folderContents` and hashes every one. The journal is deeper than N6 asks (20), so ⌘Z walks
   back a session.
5. **Optimistic then authoritative — and the UI never waits for a file.** `perform` publishes the
   reduced snapshot and returns; its ops join a serial queue (`drain`) that commits in command
   order. The store's scanned snapshot replaces the reduced one once the queue is **empty** —
   while it is not, store events are ignored, because the store cannot know the queued writes and
   its snapshot would take back what the person just did. `pullFromStore` always asks the store
   for its *current* value, so a late event can never walk the app backwards.
   **A refused write** drops everything queued behind it (reduced on top of a state the vault
   never reached), rescans, publishes the truth with the dropped renames inverted, and yields a
   `WriteFailure` on `writeFailures()`. `undo()` waits for the queue, and refuses with
   `.writeDiscarded` if a write failed while it waited — the entry below is not what the person
   meant. "Written" is the local file; nothing waits for iCloud. Collisions with files the index
   does not know (`Knowledge/`) are found on the queue, so they arrive as a `WriteFailure`, not
   as a thrown `titleCollision`.
6. The archive and the trash pick a free name on collision (they are app-owned); anywhere else a
   taken destination is `GTDError.titleCollision` for the user to resolve. Folder moves follow
   the same policy (R-5): "remove list" is a `.moveFolder` into `GTD/Trash/` and gets a free
   name, while renaming a list onto a name that exists — or moving a project into an area that
   already holds one of that name (R-7) — is the user's to resolve.
7. Housekeeping: `start()` creates the folder skeleton from `VaultLayout` if it is missing and
   otherwise **writes nothing**. `archiveCompleted` runs once per day, queued behind the first
   write of the day that landed (`queueHousekeepingIfDue`) — the vault is only written when the
   person acts on an item. A refused archive is a `WriteFailure` like any other.
   (`WritePolicy.awaited` archives inside `start()`, for the file-asserting suites.) Remembered in `housekeeping.json` next to the journal — never in the vault. The day is
   recorded **only on success**, so a failed archive is retried at the next launch rather than
   skipped until tomorrow; the reason is on `lastHousekeepingError`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDServicesTests` — 86 tests. `TestVault` builds its
backend with `.awaited`; `QueuedWriteTests` runs the production policy against a store whose
commits wait at a gate: publish-before-write, order, no walk-back on a store event, a refused
write (revert + report + discarded count), undo waiting for the queue, `stop()` flushing, opening the vault writing nothing, and the
daily archive riding behind the first change of the day — once. `ParityTests` drives 21
commands through `InMemoryBackend` and `VaultBackend` and compares a fresh scan of the vault with
the in-memory snapshot after every step; `SnapshotShape` says which fields are compared and why.
`FolderMoveTests` is the one suite here that uses `@testable`: the collision policy is a private
step of `perform`.

`InboxFlowJourneyTests` is the 2026-09-21 rework's acceptance suite, on a temp copy of the sample
vault: an action card refused first for R-3's required fields and then by the cap (writing
**nothing** either time), demote-and-file, the note renamed to the capture text with the full
dictation kept above `# Why?` (R-4); a capture into a list, completed, undone and then promoted
into Someday (L3/L4); a Knowledge note filed into an **active project's folder** (I4b/D36); trash
and undo, for a capture and for an action, byte for byte (I4c); the `+ project` chip creating an
area-less project and linking it in one command, then that project moving into an area and back
(R-8 + R-6/R-7); and a hand-written `status: backlog` note that a whole session leaves
byte-identical until its status really changes (R-1).

`ListJourneyTests` is the §5a counterpart end to end on a temp copy of the
sample vault — capture → filed into a list → finished → undone → "Make action" refused at the cap
→ demote → Next, plus create / rename / remove of the folders themselves — and every assertion is
about the **files**, not about the snapshot the backend happens to hold.
`ProjectAreaJourneyTests` is the R-6/R-7 counterpart, also on a temp copy: a project created by
name only lands in `Projects/no_area/`, giving it an area moves the folder with the reference
files inside it and rewrites the linked action's `project:` line in the same commit, one undo
restores every byte, and a move onto a taken name is refused without touching the tree.
`SyncScenarioTests` runs the situations that need two writers on one folder — two devices
logging the same routine, an undo refused after someone else wrote, a conflict copy, an evicted
file, and a rename while another view holds the old `NoteID`. `PerformanceTests` generates
a vault of any size (`GTD_BENCH_NOTES`, driven by `scripts/benchmark.sh`) and asserts the *shape*
of the work rather than the clock: one changed note is one write and one decode, whatever the
size of the vault.
