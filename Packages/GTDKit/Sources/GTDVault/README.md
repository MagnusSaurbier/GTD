# GTDVault

The only module that touches the file system.

## Public API

- `VaultStore` (protocol) — `snapshots()`, `read(path:)`, `commit(_:)`, `folderContents(_:)`
  (the files below a folder, `nil` when there is none — T02-1, what `GTDServices` hashes for a
  folder move and asks before choosing a free name), `activate()` (creates
  `VaultLayout.requiredFolders`, scans and starts watching; default no-op, so a store that needs
  no preparation is unaffected).
- `FileVaultStore` (actor) — scans, watches and commits. `init(root:layout:)` picks the platform
  pieces; the full `init(fileSystem:layout:parser:watcher:debounce:clock:today:)` is what tests use.
  Also `scan()`, `currentSnapshot`, `startWatching()`, `stopWatching()`, `close()`.
- `VaultBookmark` + `BookmarkStore` / `PathBookmarkStore` — durable folder access.
  `withAccess(to:_:)` brackets a freshly picked folder's security scope around a body (#60).
- `VaultCreator` (#60) — `create(named:in:layout:)` makes `<location>/<name>/` and
  `VaultLayout.requiredFolders` inside it, folders only; `folderName(for:)` trims and sanitises
  the typed name. `VaultCreator.Refusal` (empty/hidden name, missing location, a file of that
  name, a folder with content — `.DS_Store` aside) is thrown before anything is written; its
  `errorDescription` is the wording onboarding shows.
- `InboxWriter` — standalone capture (C1/C3); needs only the bookmark, no index, no codec.
  Writes `Inbox/<title>.md` named after the text (`CaptureText.note(for:)`); a taken name —
  including an evicted file's `.<name>.icloud` placeholder — gets ` 2`, ` 3`, …; an empty capture
  throws `InboxWriter.CaptureRefusal.empty`. Note that `VaultClassifier.conflictCopies` reports
  such a ` 2` next to its original as a possible iCloud conflict copy (a deliberate false positive).
- `VaultFileInfo` — path, size, `modified`, `created` (birth time, `nil` where unknown; not in the
  fingerprint), `isDownloaded`, `captureDate` (#89).
- `VaultFileSystem` + `PlainFileSystem` / `InMemoryFileSystem` (`moveFolder(_:to:)`,
  `createFolder(_:)` and
  `folderExists(_:)` alongside the file operations; `listEntries()` returns a
  `VaultListing` — files **and** folders from one walk; the index calls it on every refresh, and
  the two-walk default is only for a conformer that does not override it), `VaultIndex`, `VaultClassifier`,
  `VaultNoteParser` / `NoteCodecParser` (its `listItem(id:text:layout:)` is the seam for §5a),
  `VaultClassifier.listFolderName(of:)` / `misplacedListReason(of:)` /
  `isNoAreaFolder(of:)` / `noAreaNoteReason()` / `areaLessProjectHasAreaReason(_:)` (R-6),
  `VaultWatcher` / `VaultChange` (`.unknown` or a `.paths` hint) / `PollingVaultWatcher` /
  `CompositeVaultWatcher` / `NullVaultWatcher`, `VaultIndex.refresh(paths:using:)` (the targeted
  re-index behind a hint or a commit; `nil` = "this needs a walk"),
  `DebounceState` / `ChangeDebouncer`, `VaultClock`, `VaultError`.

## Invariants

1. **Nothing is ever hard-deleted.** `VaultFileSystem` has no delete method at all;
   `VaultFileOp.delete` moves the file into `GTD/Trash/` with a free name. `moveFolder` is a
   rename too — it can empty a folder's old path, never its contents.
2. `commit` is all-or-nothing: a failure rolls back what was applied. If rollback itself fails,
   `VaultError.rollbackFailed` carries both reasons — the vault is mixed and the user must hear it.
3. `commit` returns the inverse ops **already in undo order**: feeding them back into `commit`
   restores the previous state (the undo journal relies on this).
4. A `.move` never overwrites (`VaultError.destinationExists`); the caller picks another name.
   `GTDServices` does that for `Archive/` and `GTD/Trash/` and turns it into
   `GTDError.titleCollision` everywhere else.
5. **`.moveFolder` (R-5) moves the directory in one step** — one `NSFileCoordinator` call, not
   one per file — and follows the same rules: a destination taken by a file *or* a folder is
   `destinationExists`, a missing (or non-folder) source throws, the inverse is the move back,
   and a folder cannot be moved inside itself. The one sequence it cannot undo is a commit that
   moves a folder away *and* writes a file back into the old path: the old path is then a folder
   again, and the move back is refused rather than removing it (`TransactionFuzzTests` covers
   this branch). No reducer emits such a pair.
6. **`.createFolder` creates a directory and has no inverse** — a list *is* its folder (§5a), and
   removing a directory would be the hard delete of invariant 1. It is idempotent, refused only
   when a file already sits on the name, and an undo or a rollback leaves the empty folder behind.
7. **`Lists/` is read from the folder tree, not from a note** (§5a): every *direct* subfolder is
   a list, `Done/` is reserved (a list's finished log, never a list), an **empty** folder is a
   list all the same, and a markdown note directly in `Lists/` or nested deeper becomes a
   `VaultIssue` — ignored, never moved, never guessed at.
8. **`Projects/no_area/` is a folder, not an area** (R-6). `VaultFileKind.noAreaNote` is what
   `Projects/no_area/no_area.md` classifies as: it becomes a `VaultIssue` and the file is left
   exactly where it is — never decoded as an `Area`, never moved, never rewritten. A project
   inside `Projects/no_area/` whose frontmatter still names an area is reported the same way, with the
   value read as the file spells it. A project a pre-rework vault left directly under `Projects/`
   is indexed as it always was, with `area == nil`, and nothing moves it.
9. Decode failures, evicted iCloud items and conflict copies become `VaultIssue`s. Conflict
   copies are reported, never resolved, and are still indexed so nothing disappears.
10. `Action.modified` is the file mtime — the only field the codec cannot supply.
11. `GTDMarkdown.NoteCodec` is reached only through `VaultNoteParser`.

## Platform split (ARCHITECTURE §5)

Everything above is Foundation-only and runs on Linux. `Platform/` holds the files wrapped
entirely in `#if os(iOS) || os(macOS)`: `CoordinatedFileSystem` (`NSFileCoordinator`, iCloud
downloads), `SecurityScopedBookmarkStore`, `PresenterVaultWatcher` (`NSFilePresenter` + polling
safety net), `VaultPlatform+Apple`, and — `#if os(macOS)` — `FSEventsVaultWatcher`, the only
mechanism that hears an **uncoordinated** write (Obsidian, a script) when it happens; `VaultPlatform+Portable` is their non-Apple counterpart.
They compile on a Mac (`swift build` and the iOS-simulator step of `scripts/check.sh`); nothing
in them has run against a real iCloud vault yet. `CoordinatedFileSystem.moveFolder` is the one to
watch: it coordinates the *directory* with `.forMoving` and then announces the move with
`item(at:didMoveTo:)`, so presenters below it follow the tree instead of pointing at the old URL.

## Gotchas

- **An external write is on screen in ~100 ms on the Mac** (`ExternalWriteLatencyTests`, a plain
  write into a temp vault): FSEvents (50 ms latency, per-file events) → `.paths` hint → debounce
  (50 ms quiet, 500 ms ceiling) → `VaultIndex.refresh(paths:)` re-stats those files only. iOS
  has no FSEvents; there the presenter hears iCloud's and other apps' (coordinated) writes and
  passes their URLs as the hint. The 5 s poll stays underneath both.
- A change hint is never trusted: the index compares fingerprints for every hinted path and
  returns `nil` — walk the vault — for a folder, a file in a folder it has not seen (the folder
  list feeds lists and Knowledge), or more than 64 paths. `TargetedRefreshTests` fuzzes random
  external edits and compares against a cold scan after every step. A missed or duplicated
  event costs at most one extra scan; a refresh that found nothing publishes nothing.
- `commit` re-indexes through the same targeted path with the paths of its own ops (folder ops
  walk), so a write no longer costs a walk of the vault either.
- **A file in `Inbox/` without `created`** — a capture Shortcut that writes only the text,
  a note typed in Obsidian, a script — is a capture dated by the file's **birth time**
  (`VaultFileInfo.created`, `captureDate` = the earlier of birth and modification time, the
  modification time where the file system reports no birth time; `NoteCodec.decodeInboxItem(fileDate:)`),
  not a `VaultIssue` (#89). Reading never touches the file; the app's first write of the note for
  an item action stamps that date as `created:` — it must be then, because every app save is atomic
  (temp file + rename), which gives the file a new birth time. A `created` that is present but
  unreadable still is an issue. `InMemoryFileSystem` models this: a write resets the birth time,
  a move keeps it, `setDates(of:created:modified:)` sets both for a test.
- The index cache key is `size + mtime`. A second-granularity file system can hide a same-size
  edit within one second; the watcher's next poll picks it up.
- `Projects/X/X.md` is an area or a project depending on its `kind:` key — `Frontmatter.scalar`
  peeks at it for classification only; all real parsing is the codec's. The one exception is
  `Projects/no_area/no_area.md`, which is neither whatever its `kind:` says (R-6).
- A refresh costs one directory walk plus one decode **per changed file** — never a re-parse of
  the vault. What it does still cost is re-assembling the whole snapshot (`VaultIndex.snapshot`)
  and, after a commit, a full re-listing, which is what `docs/follow-ups/55-incremental-reindex.md`
  is about. Numbers: `scripts/benchmark.sh`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDVaultTests` (158 tests, never the real vault).
`FileVaultStoreTests.scansAThousandNotesAndRefreshesIncrementally` compares two wall-clock timings
(`refreshSeconds < scanSeconds`) and failed once in three full runs on a busy Mac (2026-09-21);
a re-run passed. A failure there alone is load, not a regression.
`NoAreaIndexTests` pins R-6: `no_area` is never an area, a project inside it has `area == nil`,
a legacy top-level project is still indexed, and both contradictions are reported rather than
fixed.
`TransactionFuzzTests` throws 900 random op sequences at `VaultTransaction` — puts, file moves,
folder moves and deletes — half of them against an injected write or move failure, and asserts
the three rules the vault depends on: a refused commit changes nothing outside `GTD/Trash/`, a
successful one matches a plain simulation of its own ops and its inverse restores the vault byte
for byte (or is refused without touching anything, invariant 5), and no byte that existed before
is ever gone unless a `.put` overwrote the file it lived in. Failures print the seed.
`SampleVaultScanTests` and `captureRoundTripsThroughTheCodec` are `.enabled(if:
NoteCodecParser.codecIsImplemented)`, which the finished codec satisfies, so they run.
