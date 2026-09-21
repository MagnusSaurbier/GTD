# GTDFixtures

Deterministic sample data: one snapshot in memory and the same vault as markdown files on disk.
Depends on `GTDModel` only — **not** on `GTDMarkdown`, because the codec and the vault scanner
are tested *against* these files. No SwiftUI; compiles on Linux.

## Public API

- `Fixtures.sampleSnapshot` — the whole sample vault as a `VaultSnapshot`.
- `Fixtures.today` (2026-09-19, a Saturday), `Fixtures.day(_ offset:)`, `Fixtures.date(_:_:_:_:)`,
  `Fixtures.calendar` (Europe/Berlin, +02:00), `Fixtures.reducerEnv(deviceID:)`.
- `Fixtures.lists` / `Fixtures.listItems` — the three lists of L1 and their notes.
- Named entities: `applicationsArea`, `careerArea`, `daadProject`, `erasmusProject`,
  `thesisProject`, `sideJobProject` (on hold), `flatProject` (stalled), `morningRoutine`,
  `bedtimeRoutine`, `lastReview`.
- `SampleVault.files` (path → text), `SampleVault.copyToTemporaryDirectory()`,
  `SampleVault.write(_:to:)`, `SampleVault.read(tree:)`, `SampleVault.bundleURL`.

## What the sample vault contains

6 inbox items (one deferred to review, one 11 days old), 28 actions across every status with
**Next at cap − 1** (14 of 15: 2 `in-progress` + 12 `next`), 2 areas, 5 projects (one on hold,
one stalled), one overdue waiting item (chase), two deferred and three due-soon items, the
Morning (8 steps) and Bedtime (5 steps) routines, 10 days of routine log, a `KW 37` review note,
a `Knowledge/` folder tree, and the three lists of §5a — Read (3 open + 1 in `Done/`), Watch (2)
and Wish (1). Every list folder holds a file on purpose: git does not track empty directories, so
a list whose folder held nothing would be missing from a fresh clone. `Config.md` names no
favourites, so the sample vault exercises R-5's derived default.

## Invariants

- Anchored on `Fixtures.today`, so ages, badges and heatmaps look the same on every machine.
- `Fixtures.config` (the snapshot's `config`) carries the text of `GTD/Config.md` in its
  passthrough, the way a config decoded from a vault does. Without it
  `GTDVaultTests.SampleVaultScanTests` could never find `scan(sample vault).config` equal to
  `sampleSnapshot.config` — every other entity is compared field by field there, because a
  fixture built in code has no file text to carry.
- Empty folders cannot be committed to git. The `Knowledge/` tree has none to commit, so
  `SampleVault.write(_:to:)` creates it; **every list folder instead holds at least one note**,
  so `Lists/` needs no such help and a files-only copy of the vault is the whole vault.
  "An empty folder is still a list" (L2) is covered against a temp directory instead —
  `GTDVaultTests/ListsIndexTests` and `GTDServicesTests/ListJourneyTests` (`createList`).
- `Resources/SampleVault/` is a **committed rendering of `sampleSnapshot`**, byte-for-byte.
  `SampleVaultTests.committedCopyMatchesTheRenderedSnapshot` fails when they drift.
- The renderer in `SampleVault.swift` is fixtures-only. If the codec changes a note format, change it
  here too and re-export.

## Regenerating the committed vault

```bash
cd Packages/GTDKit && GTD_EXPORT_SAMPLE_VAULT="$PWD/Sources/GTDFixtures/Resources/SampleVault" \
  swift test --filter exportSampleVault
```

## Changing a fixture

Adding one is cheap; changing an existing one breaks other targets' tests, because they assert
against these exact counts and values. Prefer adding, and regenerate the committed sample vault
afterwards (the command is in `CLAUDE.md`).
