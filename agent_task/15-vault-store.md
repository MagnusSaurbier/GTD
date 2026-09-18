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

## Contract changes

Additive only; nothing was removed or renamed. `Package.swift` untouched.

| # | Change | Where | Why |
| --- | --- | --- | --- |
| T15-1 | `commit` semantics written down: ops applied in order, all-or-nothing with rollback, inverse ops returned **already in undo order**, `.move` never overwrites. | `docs/ARCHITECTURE.md` §4 (GTDVault) | The signature said "returns the inverse ops" but not in which order. T16 feeds them straight back into `commit`, so the order is load-bearing. |
| T15-2 | `VaultError` gained `.destinationExists(path:)` and `.rollbackFailed(reason:rollbackReason:)`. | `GTDVault` (own module) | A refused overwrite and a half-applied transaction need to be distinguishable from a plain I/O error; T16 must surface the second one to the user rather than swallow it. |
| T15-3 | `InboxWriter.capture(text:at:)` grew a default `at: Date = Date()`; a second initialiser `InboxWriter(fileSystem:layout:calendar:)` was added. | `GTDVault` | T30 calls it with just the text; the tests need an injectable clock and file system. The contract initialiser `init(layout:bookmark:)` is unchanged. |
| T15-4 | `FileVaultStore` gained a full initialiser (`fileSystem:layout:parser:watcher:debounce:clock:today:`) plus `scan()`, `currentSnapshot`, `startWatching()`, `stopWatching()`, `close()`. `VaultBookmark` gained `hasSavedVault`, `clear()` and an injectable `init(store:fileURL:)`. | `GTDVault` | The contract initialisers `FileVaultStore(root:layout:)` and `VaultBookmark()` are unchanged and still pick the platform pieces. |

## Result

**Status: done.** `scripts/check.sh` passes; `GTDVaultTests` has 109 tests, 7 of them
codec-gated and therefore reported as skipped until T10 lands.

### What was built

Split so that everything except four files runs under `swift test` on Linux.

**Foundation-only (tested here):**

- `VaultFileSystem` — the I/O protocol, with `VaultFileInfo` (`path`, `size`, `modified`,
  `isDownloaded`) and a `fingerprint`. **It deliberately has no delete**, which is the
  compile-time form of "the app never hard-deletes a vault file".
- `PlainFileSystem` — `FileManager` only: recursive listing that skips dot files but keeps
  `.<name>.icloud` eviction placeholders, never follows symlinks, atomic writes, moves that
  refuse to overwrite, folder creation.
- `InMemoryFileSystem` — the fake, with injectable write/move failures and `evict(_:)`.
- `VaultClassifier` + `VaultPath` + `Frontmatter` — path to `VaultFileKind`, knowledge-folder
  stripping, conflict-copy detection, and a classification-only peek at the `kind:` key (the only
  thing that tells `Projects/X/X.md` area from project).
- `VaultNoteParser` / `NoteCodecParser` — the single seam to `GTDMarkdown.NoteCodec`, plus
  `NoteCodecParser.codecIsImplemented`, the runtime probe the gated tests use.
- `VaultIndex` — incremental index keyed on `path + size + mtime`, with a `RefreshReport`
  (added/updated/removed/reused), and the snapshot assembly: `Action.modified` from the file,
  `Project.referenceFiles` from the project folder (P6), `knowledgeFolders` from the folder tree,
  routine log trimmed to the last 14 days, `lastReview` = highest ISO week, and `VaultIssue`s for
  undecodable files, evicted iCloud items (download requested) and conflict copies.
- `VaultTransaction` — applies ops, computes inverses (`put` to previous text or delete, `move`
  to the reverse move, `delete` = move into `GTD/Trash/` with a free name so the inverse is a
  move back), rolls back in reverse on failure, reports a failing rollback instead of hiding it.
- `DebounceState` (pure: burst coalescing, 300 ms interval, 2 s ceiling) + `ChangeDebouncer`
  (actor, injectable `VaultClock`).
- `VaultWatcher` + `PollingVaultWatcher` (mtime polling, 5 s) + `NullVaultWatcher`.
- `VaultBookmark` + `BookmarkStore` / `PathBookmarkStore` — stored in Application Support, never
  in the vault; stale bookmarks are re-saved transparently.
- `InboxWriter` — timestamp filename, `-n` collision suffix, `created` frontmatter, atomic write.
- `FileVaultStore` (actor) — scan, incremental refresh, watch + debounce, commit, and a
  `SnapshotHub` that fans `snapshots()` out under a lock.

**Platform-only, wrapped entirely in `#if os(iOS) || os(macOS)`:** `CoordinatedFileSystem`
(`NSFileCoordinator` around every read/write/move, `startDownloadingUbiquitousItem`,
`ubiquitousItemDownloadingStatus`), `SecurityScopedBookmarkStore` (`.withSecurityScope` on macOS),
`PresenterVaultWatcher` (`NSFilePresenter` on the root with the polling watcher as a safety net),
and `VaultPlatform+Apple`. `VaultPlatform+Portable` is the `#if !(os(iOS) || os(macOS))` twin.

### Acceptance

All covered except where noted: commit + inverse restores every file byte for byte, partial
failure rolls back the vault *and* leaves the published snapshot untouched, a conflict copy is
reported (and still indexed, so nothing vanishes), an external edit is picked up through the
debounced watcher path, evicted iCloud items become issues and the download is requested,
1 000 notes scan well inside the budget and the incremental refresh is measurably cheaper.
`scan() == GTDFixtures.sampleSnapshot` lives in `SampleVaultScanTests` and is **gated on T10**
(see below). Tests only ever use `SampleVault.copyToTemporaryDirectory()` or temp dirs.

### Deviations and decisions

- **T10 gating.** `NoteCodec` still throws `notImplemented`, so the seven tests that need real
  parsing are `@Suite/@Test(.enabled(if: NoteCodecParser.codecIsImplemented))`. They are written
  against the real API and enable themselves with no edit once T10 lands — whoever merges T10
  should run `swift test --filter GTDVaultTests` and expect them to go from skipped to green.
  They compare ids, statuses, contexts, projects, dates, counts and config rather than whole
  values, because `NotePassthrough` contents are the codec's business.
- **`InboxWriter` renders its own two-key frontmatter** instead of calling `NoteCodec.encode`.
  A fresh capture has no unknown keys or body sections, so N2 has nothing to protect, and C1
  requires capture to work with nothing else loaded (the codec's `encode` currently
  `fatalError`s). `captureRoundTripsThroughTheCodec` pins the format to the codec once T10 lands.
- **A `.move` onto an existing path throws** rather than picking a new name: silently renaming
  would desynchronise the file from the `NoteID` in the snapshot. Trash collisions *do* get a
  free suffix, because the trash is not part of the snapshot.
- **`.delete` of a missing file is a no-op**, `.move` of a missing source throws. External edits
  make the first case normal; the second is always a bug worth surfacing.
- **Conflict-copy detection has a deliberate false positive:** `VaultLayout.actionPath` uses the
  same " 2" suffix for a genuine title collision. Over-reporting is the safe direction — an issue
  is only ever a message, and the file stays indexed and untouched.
- **`lastReview` is the highest ISO week, not the newest mtime**, so re-syncing an old note does
  not change it.
- The store's `layout` is fixed at init; a `layout` inside a decoded `GTD/Config.md` reaches the
  snapshot but does not re-point the scanner (T26/T40 would restart the store to change it).

### Files that could not be compiled on Linux (verify on a Mac)

All four under `Sources/GTDVault/Platform/`: `CoordinatedFileSystem.swift`,
`SecurityScopedBookmarkStore.swift`, `PresenterVaultWatcher.swift`, `VaultPlatform+Apple.swift`.
To verify: `scripts/check.sh` on a Mac with Xcode 26 (its `xcodebuild` step compiles them for
iOS). Most likely breakages, in order: the two-URL `NSFileCoordinator.coordinate(writingItemAt:
options:writingItemAt:options:error:)` overload used by `move`; `URLResourceKey
.ubiquitousItemDownloadingStatusKey` returning `nil` rather than `.current` for non-iCloud files;
`NSFilePresenter` conformance requiring `@MainActor` or a different `Sendable` shape under Swift 6
strict concurrency. Beyond compiling, the behaviour worth checking on device is that a
security-scoped bookmark into Obsidian's iCloud container really survives a relaunch — T01 was
skipped, so that is still an assumption (ARCHITECTURE §6).

### Gotchas for the next agents

1. **T16:** `commit` gives you the inverse ops *in undo order* — push them as they are.
   `rollbackFailed` is the one error you must show the user instead of retrying.
2. Change detection reports only *that* something changed; the index decides what to re-read. A
   missed or duplicated event costs at most one extra scan, never a wrong snapshot.
3. The index cache key is `size + mtime`. A same-size edit inside one second on a
   second-granularity file system is invisible until the next poll — do not tighten this into a
   content hash without measuring, the budget is 50 ms.
4. Nothing in `GTDVault` can hard-delete: `VaultFileSystem` has no such method. Keep it that way.
5. `InMemoryFileSystem` lives in `Sources/`, not in the tests — T16 can and should use it.
6. Use `VaultNoteParser`, never `NoteCodec` directly, so decode failures keep landing in
   `VaultIssue`.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
[11 expected "no rule to process file ... xcstrings/assetcatalog" warnings]
Build complete!

=== swift test (Packages/GTDKit)
* Test run with 109 tests in 13 suites passed after 0.309 seconds.      (GTDVaultTests)
      -> Suite SampleVaultScanTests skipped.                             (gated on T10)
      -> Test captureRoundTripsThroughTheCodec() skipped.                (gated on T10)
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 3 tests in 1 suite passed after 0.003 seconds.
* Test run with 29 tests in 3 suites passed after 0.014 seconds.
* Test run with 2 tests in 1 suite passed after 0.011 seconds.
* Test run with 3 tests in 1 suite passed after 0.004 seconds.
* Test run with 6 tests in 1 suite passed after 0.111 seconds.
* Test run with 4 tests in 1 suite passed after 0.006 seconds.
* Test run with 1 test in 1 suite passed after 0.003 seconds.
* Test run with 2 tests in 1 suite passed after 0.004 seconds.
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 1 test in 1 suite passed after 0.003 seconds.
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 2 tests in 1 suite passed after 0.003 seconds.
* Test run with 3 tests in 1 suite passed after 0.003 seconds.
* Test run with 5 tests in 1 suite passed after 0.001 seconds.

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild - package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only - verify this step on a Mac.

=== check.sh finished
```
