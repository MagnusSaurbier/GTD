# GTDVault

The only module that touches the file system.

## Public API

- `VaultStore` (protocol) — `snapshots()`, `read(path:)`, `commit(_:)`, `activate()`
  (creates `VaultLayout.requiredFolders`, scans and starts watching; default no-op, so a
  store that needs no preparation is unaffected).
- `FileVaultStore` (actor) — scans, watches and commits. `init(root:layout:)` picks the platform
  pieces; the full `init(fileSystem:layout:parser:watcher:debounce:clock:today:)` is what tests use.
  Also `scan()`, `currentSnapshot`, `startWatching()`, `stopWatching()`, `close()`.
- `VaultBookmark` + `BookmarkStore` / `PathBookmarkStore` — durable folder access.
- `InboxWriter` — standalone capture (C1/C3); needs only the bookmark, no index, no codec.
- `VaultFileSystem` + `PlainFileSystem` / `InMemoryFileSystem` (`listEntries()` returns a
  `VaultListing` — files **and** folders from one walk; the index calls it on every refresh, and
  the two-walk default is only for a conformer that does not override it), `VaultIndex`, `VaultClassifier`,
  `VaultNoteParser` / `NoteCodecParser`, `VaultWatcher` / `PollingVaultWatcher` / `NullVaultWatcher`,
  `DebounceState` / `ChangeDebouncer`, `VaultClock`, `VaultError`.

## Invariants

1. **Nothing is ever hard-deleted.** `VaultFileSystem` has no delete method at all;
   `VaultFileOp.delete` moves the file into `GTD/Trash/` with a free name.
2. `commit` is all-or-nothing: a failure rolls back what was applied. If rollback itself fails,
   `VaultError.rollbackFailed` carries both reasons — the vault is mixed and the user must hear it.
3. `commit` returns the inverse ops **already in undo order**: feeding them back into `commit`
   restores the previous state (the undo journal relies on this).
4. A `.move` never overwrites (`VaultError.destinationExists`); the caller picks another name.
   `GTDServices` does that for `Archive/` and `GTD/Trash/` and turns it into
   `GTDError.titleCollision` everywhere else.
5. Decode failures, evicted iCloud items and conflict copies become `VaultIssue`s. Conflict
   copies are reported, never resolved, and are still indexed so nothing disappears.
6. `Action.modified` is the file mtime — the only field the codec cannot supply.
7. `GTDMarkdown.NoteCodec` is reached only through `VaultNoteParser`.

## Platform split (ARCHITECTURE §5)

Everything above is Foundation-only and runs on Linux. `Platform/` holds the four files wrapped
entirely in `#if os(iOS) || os(macOS)`: `CoordinatedFileSystem` (`NSFileCoordinator`, iCloud
downloads), `SecurityScopedBookmarkStore`, `PresenterVaultWatcher` (`NSFilePresenter` + polling
safety net) and `VaultPlatform+Apple`; `VaultPlatform+Portable` is their non-Apple counterpart.
**All four are compiled blind** — verify with `scripts/check.sh` on a Mac.

## Gotchas

- Change detection reports only *that* something changed; the index decides what to re-read, so a
  missed or duplicated event costs at most one extra scan.
- The index cache key is `size + mtime`. A second-granularity file system can hide a same-size
  edit within one second; the watcher's next poll picks it up.
- `Projects/X/X.md` is an area or a project depending on its `kind:` key — `Frontmatter.scalar`
  peeks at it for classification only; all real parsing is the codec's.
- A refresh costs one directory walk plus one decode **per changed file** — never a re-parse of
  the vault. What it does still cost is re-assembling the whole snapshot (`VaultIndex.snapshot`)
  and, after a commit, a full re-listing, which is what `docs/follow-ups/55-incremental-reindex.md`
  is about. Numbers: `scripts/benchmark.sh`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDVaultTests` (112 tests, never the real vault).
`TransactionFuzzTests` throws 600 random op sequences at `VaultTransaction`, half of them
against an injected write or move failure, and asserts the three rules the vault depends on: a
refused commit changes nothing outside `GTD/Trash/`, a successful one matches a plain simulation
of its own ops and its inverse restores the vault byte for byte, and no byte that existed before
is ever gone unless a `.put` overwrote the file it lived in. Failures print the seed.
`SampleVaultScanTests` and `captureRoundTripsThroughTheCodec` are `.enabled(if:
NoteCodecParser.codecIsImplemented)`, which the finished codec satisfies, so they run.
