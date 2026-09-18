# T15 — Vault store (`GTDVault`)

**Wave 1 · needs T00 · integration tests need T10 · informed by T01's report if available**

## Model recommendation

**Difficulty:** Hard · **Recommended model:** Opus

File coordination, security-scoped access, iCloud eviction and conflict copies, debounced change detection, incremental indexing on an actor, rollback on partial failure — concurrency plus platform quirks plus the user's real data. This is where data-loss bugs would come from. Opus, and review the result carefully even so.

## Goal

The only module that touches the file system: durable folder access, coordinated I/O, change
detection, and building `VaultSnapshot`s from files.

## Requirements covered

N1, N2, N3, C3, ARCHITECTURE §7 (all sync safety rules).

## Owns

`Sources/GTDVault/`, `Tests/GTDVaultTests/`.

## Deliverables

- `VaultBookmark`: create from a picked URL, persist (Application Support), resolve with stale
  handling, start/stop security-scoped access; works on iOS and sandboxed macOS.
- `CoordinatedFileSystem` (protocol + real + in-memory fake): read, atomic write, move, list,
  attributes, all via `NSFileCoordinator`; creates intermediate folders.
- `FileVaultStore: VaultStore`:
  - initial scan → decode every relevant file with `NoteCodec` → `VaultSnapshot`; undecodable
    files, evicted iCloud items (trigger download) and conflict copies become `VaultIssue`s;
  - incremental re-index on change (per-file cache keyed by path + mtime + size);
  - `commit(ops)` applies ops in order, returns inverse ops (put ↔ previous content or delete,
    move ↔ reverse move, delete = move into `GTD/Trash/` so the inverse is a move back);
    all-or-nothing as far as feasible: on failure roll back what was applied;
  - change detection using the mechanism T01 recommends (default: `NSFilePresenter` on the root
    + debounce 300 ms; fall back to polling mtime every 5 s while foregrounded);
  - snapshots are emitted on a background actor; never block the main thread.
- `InboxWriter`: standalone capture writer (timestamp filename, collision suffix, `created`
  frontmatter) that needs only the bookmark — used by App Intents (T30).
- Fills `Action.modified` from file attributes and `VaultSnapshot.lastReview` from the newest note under `GTD/Reviews/`.
- `referenceFiles` for projects, `knowledgeFolders` tree listing, routine log limited to the last 14 days.
- Performance budget: 1 000 notes scan < 500 ms on a Mac, incremental update < 50 ms.

## Acceptance

- Tests run against `SampleVault.copyToTemporaryDirectory()`: scan equals `GTDFixtures.sampleSnapshot`
  (modulo ordering), external edit is picked up, commit + inverse restores byte-identical files,
  partial failure rolls back, conflict copy is reported, 1 000-note performance test.
- No code path can hard-delete a vault file.
- `scripts/check.sh` passes (file-coordination code must also compile for iOS).

## Result

_(fill in when done)_
