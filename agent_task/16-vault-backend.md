# T16 — Vault backend & undo (`GTDServices`)

**Wave 2 · needs T10, T11, T15**

## Model recommendation

**Difficulty:** Hard · **Recommended model:** Opus

Snapshot diff → file transaction, undo with remote-change detection, wikilink upkeep on rename inside the same transaction, optimistic emission vs file-watcher echo. Correctness-critical integration of T10/T11/T15 with subtle ordering and consistency issues; parity with `InMemoryBackend` must hold.

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

## Contract changes

| # | Change | Where | Why |
| --- | --- | --- | --- |
| T16-1 | `VaultStore` gained `func activate() async throws`, with a **no-op default implementation** in `GTDVault`. `FileVaultStore` implements it as: create `VaultLayout.requiredFolders`, `scan()`, `startWatching()`. | `docs/ARCHITECTURE.md` §4, `Sources/GTDVault/VaultStore.swift`, `Sources/GTDVault/README.md` | T16 owes the housekeeping "the folder skeleton exists", and `VaultStore` was the backend's only window on the vault. Creating folders from `GTDServices` would have meant a second module touching the file system (ARCHITECTURE §2). Additive: every existing conformance keeps compiling. |
| T16-2 | `GTDServices` depends on `GTDAppCore` (target and test target in `Package.swift`). | `Packages/GTDKit/Package.swift`, ARCHITECTURE §2 | `VaultBackend` must conform to `GTDAppCore.GTDBackend`; the `GTDServices` README (T00) already said T16 would add it. No cycle — `GTDAppCore` depends on `GTDModel` alone. The forbidden direction, Feature → `GTDServices`, is untouched. |
| T16-3 | `Fixtures.sampleSnapshot.config` now carries the text of `GTD/Config.md` in its passthrough (new `Fixtures.config`). | `Sources/GTDFixtures/SampleSnapshot.swift`, `Sources/GTDFixtures/README.md` | The red test on the branch. See "The red test" below. |
| T16-4 | `SnapshotDiff.ops` gained a defaulted `timeZone: TimeZone = .current` parameter (T10-1's convention). | `Sources/GTDServices/SnapshotDiff.swift` | So a command and the timestamps it writes agree; `VaultBackend` passes `env.calendar.timeZone`. Existing call sites compile unchanged. |
| T16-5 | `ServiceError` is now `.nothingToUndo` / `.undoStale(path:)`; the placeholder case `.notImplemented(String)` is gone. | `Sources/GTDServices/ServiceError.swift` | Nothing outside `GTDServices` referenced it (checked), and a shipped error enum should only contain errors that can happen. |

Undo labels deviate from this brief's example and follow STYLEGUIDE §3.8/§6.3 instead
(`Moved to Backlog`, not `Filed 'Call bank' to Next`) — the style guide wins on wording
(ARCHITECTURE §5), and it keeps both backends' toasts identical. Recorded in ARCHITECTURE §6.

## Result

**Status: done.** `scripts/check.sh` passes (exit 0); `GTDServicesTests` has **40 tests**, all
Linux-clean, and the red `SampleVaultScanTests` test is green again.

### The red test (first deliverable)

`GTDVaultTests.SampleVaultScanTests.scanOfTheSampleVaultEqualsTheSampleSnapshot` failed on
`scanned.config == expected.config`. The two configs agreed on every field *except*
`NotePassthrough`: `GTDMarkdown` stores a note's original text there on decode (that is what makes
N2 hold), so a config read from `GTD/Config.md` carries that file, while
`Fixtures.sampleSnapshot.config` was `GTDConfig.default` — built in code, carrying nothing. Every
other entity in that test is compared field by field for exactly this reason; `config` was the one
compared as a whole value.

Fixed in `GTDFixtures` (`Fixtures.config`), because the fixture is the thing that claims to
describe the sample vault: it now carries `SampleVault.renderConfig(.default)`, the very text
`SampleVault` renders into the committed vault, so the two cannot drift and `GTDFixtures` still
does not depend on `GTDMarkdown`. Nothing was relaxed — the test compares the whole `GTDConfig`,
passthrough included, and `GTDMarkdownTests`' "encoding `sampleSnapshot` reproduces the committed
vault byte for byte" stays green.

### What was built (`Sources/GTDServices`, ~700 lines + ~900 lines of tests)

- **`VaultBackend`** (actor, `GTDBackend`): reduce → diff → one `commit` → undo journal →
  publish. `start()`/`stop()` bracket its life and `perform`/`undo` start it lazily, so it is
  safe standalone. Housekeeping on start: folder skeleton, then `archiveCompleted` once per day
  (remembered in `housekeeping.json` beside the journal, never in the vault).
- **`SnapshotDiff`**: old + new snapshot + `extraOps` → ordered ops. Honours T00-1 (a path named
  in `extraOps` is owned by it), turns an unclaimed removal into `.delete` (= trash), recognises
  a rename as "move, then write only if the content also changed", and handles the three
  collections that are not `[Entity]`: config, the `KW` review note (T00-4) and the routine log,
  grouped per day **and device** so this device never rewrites another's file.
- **`UndoJournal`** (actor): persisted JSON in Application Support, 20 entries, each with the
  inverse ops as `commit` returned them and a content hash per file it would touch.
  `ServiceError.undoStale(path:)` when any of them moved since.
- **`UndoLabel`**, **`ServiceError`**, **`ContentHash`** (FNV-1a; CryptoKit does not exist on Linux).

### Decisions worth knowing

1. **Write only what changed.** A `.put` is emitted only when `NoteCodec.encode(new) !=
   NoteCodec.encode(old)`. Since the codec patches the text it kept in the passthrough, that is
   exactly "the file would change" — so untouched notes keep their mtime (the staleness signals
   read it) and no undo entry hashes a file nobody wrote.
2. **Collisions.** `Archive/` and `GTD/Trash/` are app-owned, so a taken destination gets a free
   ` 2` name (T11 warned: those moves keep the source file name, and `VaultStore` never
   overwrites). Everywhere else — a knowledge note, a rename — a taken destination becomes
   `GTDError.titleCollision`, which the UI already handles. The app never renames around a file
   the *user* named.
3. **Optimistic emission.** After a successful commit the backend asks the store for its current
   snapshot; if the store has moved since we last looked (`FileVaultStore` re-indexes inside
   `commit`) that authoritative one is published, otherwise the reduced one. Never the value the
   `AsyncStream` handed us — asynchronous delivery means a yielded snapshot can be older than what
   the store already knows, and publishing it walks the app backwards. Three intermittent test
   failures were exactly that bug before the design was tightened; a `generation` counter now
   drops any store read that a command overtook.
4. **Undo depth.** The journal keeps 20 entries and each is verified against the files on its own,
   so ⌘Z walks back through a session; `InMemoryBackend` still restores one snapshot. Both satisfy
   N6 (ARCHITECTURE §6). Undoing the *creation* of a note leaves the note in `GTD/Trash/` —
   `VaultFileSystem` has no delete at all, so that tombstone is the price of "never hard-delete".

### Tests (40)

- `ParityTests` — a 21-command script (every `GTDCommand` case) through `InMemoryBackend` and
  `VaultBackend`, comparing **a fresh scan of the vault** with the in-memory snapshot after every
  step, plus equal outcomes for a refused command and equal undo labels. `SnapshotShape` documents
  the four things it does not compare (`NotePassthrough`, `Action.modified`, `issues`,
  `knowledgeFolders`) and why each is not a backend difference.
- `VaultBackendScenarioTests` (15) — file-content assertions on a temp copy of the sample vault:
  all five inbox decisions, the cap error leaving every byte untouched, completion writing action
  *and* project note, a promoted step being ticked, rename + wikilink upkeep in one transaction,
  "turn into project", the archive (including the ` 2` collision and once-a-day), the folder
  skeleton, the `KW` note, the routine log, a rolled-back failing write, and a refused knowledge
  collision.
- `UndoTests` (8) — byte-identical restore, rename undo, refusal after a remote edit and after
  something took the old name, the three non-undoable commands, journal persistence across a
  "relaunch", multi-level undo, 20-entry cap.
- `SnapshotDiffTests` (11) and `SnapshotEmissionTests` (3, against a store that never re-indexes,
  so the optimistic path is observable).

### Open issues for later tasks

- **Archiving leaves a stale wikilink.** When `archiveCompleted` moves an action out of
  `Actions/`, the reducer does not retarget `ProjectStep.promotedTo`, so a promoted step keeps
  pointing at the old path (the sample vault's DAAD project shows it). The backend deliberately
  does not "fix" this itself: the link lives in the snapshot, so rewriting it here would make the
  backend disagree with the reducer and break parity. It is a one-line change in
  `Reducer.archiveCompleted` (retarget to the archive path) — **T41/T11 decision**, not mine.
- **`FeatureOverviewTests.ActionEditModelTests` is flaky** (~3 failures in 8 runs, alternating
  between `aSnapshotArrivingMidEditClobbersNeitherSide` and
  `refreshAdoptsRemoteValuesOnlyForUntouchedFields`). It is T25's debounced autosave racing its
  own `refresh()`; it is unrelated to this task (it never touches `GTDServices` or the config
  fixture) and it fails in isolation too. Worth fixing before T40.
- **T41:** `InMemoryBackend` still has a private `isUndoable` and a private label table; both are
  now duplicated in `GTDServices`. Moving `UndoLabel` into `GTDAppCore` and calling
  `Rules.isUndoable` in both would make `ParityTests.undoLabelsAgree` structurally true.
- **T40:** call `VaultBackend.start()` at launch (it is idempotent) and show `ServiceError`/
  `VaultError.rollbackFailed` through `AppModel.lastError` — a failed rollback must be told to the
  user, never retried.

### Files that could not be compiled on Linux

**None.** `GTDServices` is Foundation-only; every source and test file here builds and runs under
`swift test` on Linux. The one shared file I touched in `GTDVault`
(`VaultStore.swift`, T16-1) is Foundation-only as well.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete! (1.56 secs)
=== swift test (Packages/GTDKit)
Build complete! (2.33 secs)
✔ Test run with 109 tests in 13 suites passed after 1.448 seconds.   (GTDVaultTests, incl. SampleVaultScanTests)
✔ Test run with  40 tests in  5 suites passed after 3.250 seconds.   (GTDServicesTests)
✔ Test run with 134 tests in  8 suites passed after 0.019 seconds.   (GTDModelTests)
✔ Test run with 108 tests in  6 suites passed after 0.203 seconds.   (GTDMarkdownTests)
…all other targets' suites passed…
=== docs check
check-docs.sh: ok
=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.
=== check.sh finished
```

(exit 0. The 11 `no rule to process file … xcstrings/assetcatalog` warnings are T00's expected ones.)
