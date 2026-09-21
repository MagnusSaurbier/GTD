# T41 — QA, traceability & hardening

**Wave 3 · after T40**

## Model recommendation

**Difficulty:** Hard (judgment-heavy) · **Recommended model:** Opus

An adversarial audit is only worth as much as the auditor: tracing every requirement to evidence, hunting data-safety violations, designing sync torture tests. A weaker model tends to confirm rather than challenge. The follow-up fixes it spawns can go to Sonnet.

## Goal

Prove the app meets REQUIREMENTS v1 and is safe to point at the real vault.

## Owns

`docs/TRACEABILITY.md`, `docs/MANUAL_TEST.md` (extend), new tests anywhere; bug fixes anywhere
(keep them small and list each in Result; large ones become follow-up task docs `5x-*.md`).

## Deliverables

1. **Traceability matrix:** every requirement ID (N1–N6, C1–C4, I1–I7, A1–A5, P1–P7, W1–W2, D1–D3,
   E1–E4, R1–R6, §10 steps, M1–M6) → implementing module, test(s), status (met / partial / missing) with evidence.
2. **Data-safety review** of everything that writes: confirm ARCHITECTURE §7 rules hold; grep for
   `FileManager` use outside `GTDVault`; confirm no hard deletes; fuzz the codec with the sample
   vault + mutated files; verify unknown frontmatter survives every command (golden-file tests).
3. **Sync torture tests** on a temp vault: external edits during a commit, rename while open in
   detail view, conflict copies, evicted-file placeholders, two simulated devices writing routine logs for the same day.
4. **"No lying defaults" audit:** walk every form; no pre-filled values at all; the only proposals (follow-up +7 d,
   last-used knowledge folder) render as *suggested* chips/rows and are not persisted until confirmed. Also run the STYLEGUIDE §9 checklist over every screen.
5. **Performance:** cold launch to usable Next view with 1 000 notes; snapshot rebuild; typing latency in the detail editor.
6. **Accessibility pass** (VoiceOver through inbox card + routine runner, Dynamic Type XXL, keyboard-only on Mac).
7. **First-real-use checklist** for the user: back up vault → run T02 migration dry run → apply →
   pick vault in the app → first weekly review to settle Next vs Backlog.

8. **Docs drift check:** list every place where CLAUDE.md / ARCHITECTURE / module READMEs disagree with the code as input for T42 (list only — T42 fixes).

## Acceptance

- `docs/TRACEABILITY.md` complete; every "partial/missing" has a follow-up task doc.
- All new tests pass in `scripts/check.sh`; no test touches the real vault.

## Result

**Status: done.** Every deliverable of this brief is complete. T41 ran in three passes with
different scopes; this Result covers all of them.

| Pass | Scope | Deliverables |
| --- | --- | --- |
| 1–2 | cross-module correctness, data-safety fuzzing, the blind SwiftUI + STYLEGUIDE §9 review, the named duplication cleanup | 2, 4, 8, part of 3 |
| 3 | traceability, performance, accessibility, the rest of 3, the first-real-use checklist | 1, 3, 5, 6, 7 |

`scripts/check.sh` exits 0 with **851 tests** (820 before T41 started, 838 after pass 2).

Two deliverables are finished only as far as a Linux container can take them, and say so where
someone will read it: the accessibility pass is a read-through plus code fixes, with
`docs/MANUAL_TEST.md` §6 holding everything that needs a device; the performance work measures
and fixes what a debug build here can measure, and `agent_task/55-incremental-reindex.md` holds
the one cost it found but did not remove.

### Deliverable 1 — `docs/TRACEABILITY.md`

Every requirement ID of REQUIREMENTS v1 — N1–N6, C1–C4, I1–I7, A1–A5, P1–P7, W1–W2, D1–D3,
E1–E4, R1–R6, §10's four steps, M1–M6 — plus §12's out-of-scope list, each mapped to the module
and the tests that implement it, with a status and the evidence.

The status legend has a fourth value the brief did not ask for, because without it the matrix
would lie: **done (blind)**. It means implemented in platform-only code that nothing in this
project can compile, so the matrix says *implemented* and only a Mac says *works*. Most of the UI
is in that state and pretending otherwise would have been the single most misleading thing this
document could do.

**Six requirements come out partial**, and each has a brief rather than a sentence:

| Brief | Closes | Blocked on |
| --- | --- | --- |
| `50-mac-keyboard-map.md` | E3 — `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are not in the menu bar | Gate 2 |
| `51-search-across-lists.md` | E1/E3 — `⌘F` reaches only `FeatureOverview`'s lists | Gate 2 |
| `52-notification-actions-and-widget.md` | D2/R3 — notification actions, the routine widget, a Shortcuts picker | Gate 2 |
| `53-stale-write-guard.md` | N3 — a write built on a pre-rename snapshot duplicates a note | nothing |
| `54-filed-at-record.md` | §10.3 — "captured vs processed" is an approximation | two real weekly reviews |
| `55-incremental-reindex.md` | performance — a commit re-lists and re-assembles the whole vault | nothing |

Three requirements are **deferred by design** with the reason and the decision in the row rather
than a brief: project rename (ARCHITECTURE §6 — the folder is the project's identity), the Next
list never being truncated to the cap (an over-cap vault must stay repairable), and a routine run
left open across midnight (a consequence of one log file per day, documented in
`FeatureRoutines/README.md`; no log entry is ever wrong, a step may be re-asked).

§12 is checked the opposite way round — that nothing implements it. A repo-wide grep for
`openai`, `anthropic`, `llm`, `embedding`, `EventKit`, `Reminders`, `CRM`, `energy`, `milestone`,
`recurring`, `PHPicker`, `photoLibrary`, `UIActivity` finds no matches, and neither does one for
`URLSession`/`http` (N1's "fully offline" is structural, not a setting).

**One gap the matrix exposed that is nobody's follow-up:** `scripts/check.sh` does not run
`Tools/migrate/tests/` (40 tests) — `pytest` is not installed in the build-out container and the
gate has to stay green without it. Recorded in the §11 section and in `TEST-INSTRUCTIONS.md`.

### Deliverable 5 — performance

`GTDServicesTests/PerformanceTests` generates a vault of any size (`GTD_BENCH_NOTES`) and drives
it through the **real** stack; `scripts/benchmark.sh` runs it and prints the numbers.

Its assertions are **structural, never wall-clock** — "the refresh re-read one file, not 1 000",
"the command wrote one file, not 1 000", "doubling the projects does not square the work". A
container's clock is not a phone's, so a timing assertion would only have produced a flaky test.

It found three pathologies. All three are fixed, and the numbers are from this machine, debug
build (`swift test` never optimises), 1 000 action notes / 1 084 files:

| | before | after |
| --- | --- | --- |
| one `setStatus` end to end | **4 432 ms** | **280 ms** |
| `Rules.projectRows` | 26.9 ms | 1.1 ms |
| `Rules.stalledProjects` | 13.6 ms | 0.6 ms |
| refresh with nothing changed (on disk) | 335 ms | 240 ms |
| cold scan of the whole vault | 1 017 ms | 914 ms |

1. **`SnapshotDiff` re-encoded every note in the vault, twice, on every command.** `encode` is a
   pure function of the entity, so equal entities encode identically; the diff now short-circuits
   on equality and an unchanged note costs a comparison instead of two encodes. This is the 4.4 s
   → 280 ms line, and it got worse linearly with the size of the vault.
2. **`Rules.projectRows` / `stalledProjects` were O(projects × actions)** — they asked
   `visibleActions` once per project. One pass bucketing the visible actions by project gives the
   same answers. These run on every snapshot, for every view that shows a projects list or a
   stalled badge.
3. **Every index refresh walked the vault tree twice** (`listFiles` + `listFolders`), which on a
   real iCloud vault is two `NSFileCoordinator` reads of the whole folder. `VaultFileSystem`
   gained `listEntries()` — one walk, both listings — with a defaulted two-walk implementation so
   any other conformer still works.

The rest of the picture, unchanged and recorded rather than fixed: the cold scan is one read and
one decode per file (0.55 ms per note here, debug) and an incremental refresh re-reads exactly
the files that changed. What a command still pays for is the full re-listing and snapshot
re-assembly that follow a commit — ~240 ms of the 280 ms at 1 000 notes, ~690 ms of 750 ms at
3 000. That is `agent_task/55-incremental-reindex.md`; it is a correctness-sensitive change
(an index that trusts its own ops can drift from disk), which is why it is a brief and not a
patch here.

Cold launch, typing latency and scroll smoothness need a device and are `docs/MANUAL_TEST.md` §7.

### Deliverable 6 — accessibility

By reading, as the brief scopes it. The clear omissions are fixed; the judgement calls are in
`docs/MANUAL_TEST.md` §6 as a sweep someone with a device can actually run.

Fixed:

- **`RoutineHeatmap` carried a whole week of results by colour and position alone**, while its
  own doc comment claimed "each cell's accessibility value spells out what it means" — the cells
  were `.ignore`d children. Each row is now one VoiceOver element whose value reads
  `done Mon, Tue; skipped Wed; nothing logged Thu, Fri` — and "nothing logged" is kept distinct
  from "skipped", because in a routine log they mean opposite things. The wording moved to
  `DesignSystem/Components/HeatmapContent.swift`, **outside** the SwiftUI guard, so it is
  unit-tested on Linux (`DesignSystemTests/AccessibilityTextTests`) instead of being a claim.
- **Fixed frames around text** clip at the accessibility sizes: the heatmap grid (a hard 120 pt
  row label with `lineLimit(1)`), `Badge`'s `frame(height: 20)`, and the review wizard's 220 pt
  rail. All three are `@ScaledMetric` now.
- **`ActionRow` and `ProjectRow` read their `·`-joined meta line to VoiceOver verbatim.**
  `Copy.spoken` composes a comma-separated phrase for the label while `Copy.metaLine` keeps the
  middle dots on screen. `ProjectRow` had no accessibility at all.
- **`Done` was the one swipe action in the app with no context-menu twin** — i.e. unreachable on
  the Mac (no swipes at all) and with VoiceOver. Added to the Next row's menu. Every other swipe
  in the app was already mirrored; that was checked row by row.

Checked and found correct, so left alone: the inbox card exposes all eight card targets plus
undo as `accessibilityActions` (§8's "all 8 targets" requirement); `Chip` announces
unset/suggested/confirmed and the selected trait; `Badge` reads in full words through
`BadgeContent.accessibilityLabel`; `StatTile` and `ReviewWizardRail` compose their own labels;
Reduce Motion is honoured at every animation *and* at the validation shake and the card rotation;
Reduce Transparency falls the glass bars back to a solid card with a hairline; Increase Contrast
thickens chip outlines.

Not fixed, deliberately: `RewardMoment`'s `.font(.system(size: 56))` (STYLEGUIDE §2.3 forbids it,
but changing it blind changes how the only two reward moments look — already
`TEST-INSTRUCTIONS.md` "Unresolved" #1, now also a checkbox in `docs/MANUAL_TEST.md` §6), and the
22 pt / 20 pt control glyphs, which are affordances rather than text.

### Deliverable 3 — the rest of the sync torture tests

"Rename while open in detail view" is now covered on real files, in two halves, because the two
halves have different answers:

- **In-app** (`renamingANoteThatIsOpenElsewhereNeverResurrectsTheOldFile`): the old path is gone,
  the body and the unknown frontmatter travelled, the project's step link followed in the same
  commit, and the stale `updateAction` an open view would send next is refused with
  `.notFound` — the old file is not recreated.
- **Across two devices**
  (`aDeviceWritingFromABeforeTheRenameSnapshotDuplicatesRatherThanLoses`): a device whose
  snapshot predates the rename writes the old path and the vault ends up with **two** notes.
  Nothing is lost — both files are intact — so this is a documented limitation rather than a
  T41 bug fix, and the test pins the current behaviour so it cannot get quietly worse.
  `agent_task/53-stale-write-guard.md` is the fix.

`ActionEditModel` already handles its half correctly (it re-points itself after its own rename
and refuses to write when the note disappeared under it); that was verified by reading and is
covered by the existing `FeatureOverviewTests`.

### Deliverable 7 — first-real-use checklist

`docs/MANUAL_TEST.md` §9, in the order the brief asks for: back the vault up **outside iCloud**
and check the backup opens → quit Obsidian everywhere and let the sync settle → migration dry run
(with the script's own tests first) → work every "needs a decision" item → `--apply`, then read
ten notes by hand and re-run to confirm it is idempotent → point the app at it and relaunch once
→ the first weekly review, which is where M1's `to-do` items and M2's who-less waiting items are
actually settled → then leave it alone for a week before tuning the thresholds.

The file's banner used to say "never point the app at the real vault", which §9 would have
contradicted. It now says which sections use a copy, that §9 is the deliberate exception, and
that CLAUDE.md rule 1 — no *agent* touches the real vault — is unchanged by it.

### Bugs found and fixed

Each one is a real defect, found by a test or by reading; all fixes are small and none disables
anything. 1–12 are from passes 1–2, 13 from pass 3.

| # | Where | What was wrong |
| --- | --- | --- |
| 1 | `GTDAppCore/InMemoryBackend.swift`, `GTDServices/UndoLabel.swift` | Two private copies of the N6 undoable rule and the label table. `UndoLabel` moved to `GTDAppCore`; both backends now call `Rules.isUndoable` (T11/T16 open item). |
| 2 | `GTDModel/Reducer/Reducer.swift` | `archiveCompleted` left `ProjectStep.promotedTo` pointing at the old `Actions/` path — a dead wikilink in the project note. It retargets to the archive path (T16 open item). |
| 3 | `GTDVault/InboxWriter.swift`, `App/AppComposition.swift` | The bookmark was resolved *after* scoped access started, so "never picked", "saved but unresolvable" and "access refused" were one message and `CaptureError.bookmarkStale` was unreachable (T30 gotcha #1). |
| 4 | `FeatureReview/ReviewSession.swift` | `markStalledHandled` trusted `WhatsNextSheet`; closing the sheet without promoting dropped a stalled project out of the §10.1.4 sweep. It now verifies the project is no longer stalled (T27 open item). |
| 5 | `GTDMarkdown/NoteCodec.swift` | **Data loss.** `decodeRoutineLog` read a damaged `entries:` (a scalar or a mapping instead of a list) as "no entries". `encodeRoutineLog` regenerates the file, so the next routine step logged that day would have overwritten the day's history with an empty log. It now throws `.unreadable`, which `GTDVault` surfaces as a `VaultIssue` and never writes over. Found by the damaged-file fuzz. |
| 6 | `FeatureWaiting/WaitingViews.swift` (10 call sites), `FeatureOverview/ActionListView.swift` | Every row command was `try? await model.send(…)`. "Move to Next" on a waiting item while Next is at the cap, and un-deferring an item the defer × Next rule refuses, silently did nothing — the lying UI STYLEGUIDE §1 forbids. |
| 7 | `App/PhoneShell.swift`, `FeatureOverview/OverviewView.swift` | `InboxProcessingView` carries its own toolbar (card counter, `⌘Z` undo, `Done`) but no navigation container, and neither presenter supplied one — only the previews did. The forced processing session would have had no visible way out on either platform. |
| 8 | `FeatureOverview/OverviewView.swift` | `VaultIssuesView` was presented in a bare sheet. On the Mac that is a trap: it brings only a `.navigationTitle`, no close control. |
| 9 | `App/GTDApp.swift` | The `Scene` body used three consecutive `#if`s, two continuing a postfix modifier chain and the third opening a `Settings` *statement* — the shape blind-written scene builders most easily get wrong. Now one `#if os(macOS)/#else` around whole scenes. |
| 10 | `DesignSystem/Tokens/Colors.swift` | `dynamicContrast` read `NSWorkspace.shared` inside `NSColor`'s dynamic provider: a main-actor hop out of a nonisolated closure under Swift 6, and it tracked Increase Contrast only by luck of redraw. It now matches the `NSAppearance` it is handed against the four `aqua`/`accessibilityHighContrast…` names. |
| 11 | `FeatureInbox/InboxProcessingView.swift` | `InboxZeroView` drew STYLEGUIDE §5.1's reward moment itself, without the `signalDone` check badge, and fired its `.success` haptic on every processed card. It composes `DesignSystem.RewardMoment.inboxZero` now. |
| 12 | `App/AppComposition.swift` | The daily `archiveCompleted` was `try?`. A failed archive — including `VaultError.rollbackFailed`, which T15 says must never be silent — is now reported. |
| 13 | `GTDServices/VaultBackend.swift` | The other half of #12, found while tracing A5. `runHousekeeping` recorded the day **before** checking whether the archive succeeded, so a vault that was busy, read-only or half-synced at launch was skipped until tomorrow — and the doc comment claimed the failure was "logged as an issue", which it was not. The day is recorded only on success; the reason is on `lastHousekeepingError`. |

### Contract changes

| # | File | Change |
| --- | --- | --- |
| T41-1 | `Packages/GTDKit/Sources/GTDAppCore/AppModel.swift` | Additive: `perform(_ command:) async -> Bool` and `report(_ work:) async -> Bool`. A refused command lands in `lastError`, which the shell already shows in one alert. Views with a flow of their own for the error (the cap sheet, the waiting sheet) keep using `send` and are untouched. Module README updated. |
| T41-2 | `Packages/GTDKit/Sources/GTDVault/VaultFileSystem.swift` | Additive: `VaultListing` and `VaultFileSystem.listEntries()`, **with a default implementation** that calls the two existing listings, so every existing conformer still compiles. `PlainFileSystem`, `InMemoryFileSystem` and `CoordinatedFileSystem` override it to walk once. `VaultIndex.refresh` calls it. Not part of ARCHITECTURE §4's frozen contracts; module README updated. |
| T41-3 | `Packages/GTDKit/Sources/GTDServices/VaultBackend.swift` | Additive: `lastHousekeepingError` (bug #13). |
| — | `Packages/GTDKit/Sources/GTDAppCore/UndoLabel.swift` | Moved here from `GTDServices` and made public (bug #1). No signature changed. |
| — | `DesignSystem` | Additive tokens so feature code holds no literal: `Symbols.moveUp/moveDown`, `Typo.rowIcon/controlGlyph`, `Copy.processedSummary`, and (pass 3) `Copy.metaLine`/`Copy.spoken` plus `HeatmapSpeech`; `HeatmapCellState` moved out of `ReviewPieces.swift` into the unguarded `HeatmapContent.swift` — same module, same name, no call site changed. |

`Packages/GTDKit/Package.swift` and ARCHITECTURE §4 are untouched.

### New tests (+31 over the three passes, and five suites that did not exist)

- `GTDServicesTests/EndToEndJourneyTests` — one week through the **real** stack (`AppModel` →
  `VaultBackend` → `FileVaultStore` → `PlainFileSystem`, temp copy of the sample vault):
  external capture → file to Next → the cap refuses and writes nothing → Backlog → promote a
  project step → waiting needs who + follow-up → two levels of undo byte for byte → the `KW`
  note decoded back off disk (`systemFixNotes`, T27's open item) → a cold re-scan agreeing with
  the app. Plus the archive-retarget case and backend undo-parity.
- `GTDServicesTests/SyncScenarioTests` — N3 §7, six scenarios: two devices with different device
  ids logging the same routine on the same day; an undo refused after another writer touched the
  file; a conflict copy reported and never rewritten; an evicted iCloud file; and the two rename
  scenarios above.
- `GTDMarkdownTests/FuzzRoundTripTests` — a seeded SplitMix64 generator builds ~1 800 action,
  project and inbox notes (shuffled key order, block vs flow lists, nested mappings, block
  scalars, comments, unknown keys, unknown and oddly-spelled headings, CRLF, BOM, no final
  newline) and asserts both halves of N2 on each; then damages every sample-vault file twelve
  ways and requires each result to round-trip **or** be refused. Failures print the seed.
- `GTDVaultTests/TransactionFuzzTests` — 600 random op sequences, half against an injected
  write/move failure: a refused commit changes nothing outside `GTD/Trash/`, a successful one
  matches a plain simulation of its own ops and its inverse restores the vault byte for byte,
  and no byte that existed before is ever gone unless a `.put` overwrote the file it lived in.
- `GTDAppCoreTests/ErrorSurfacingTests` — `perform`/`report` (bug #6).
- `GTDServicesTests/PerformanceTests` — the benchmark suite above.
- `DesignSystemTests/AccessibilityTextTests` — what VoiceOver reads for a heatmap row and for a
  row's meta line, including "nothing logged" never being read as "skipped".
- `GTDServicesTests/VaultBackendScenarioTests` — a failed archive is retried at the next launch
  (bug #13).

Two rewrites of a *damaged* file are deliberate and are now pinned by tests rather than being
accidents: a note that lost its `kind:` gets it back (it is otherwise unclassifiable), and a
file whose frontmatter lost its closing `---` gets a fresh frontmatter block **above** its
unchanged text. Nothing is deleted in either case.

### Deliverable 2 — data-safety review

The invariants are *tested* rather than written up as prose (`TransactionFuzzTests`,
`FuzzRoundTripTests`, `SyncScenarioTests`). What the grep audit found, for the record: the only
code outside `GTDVault` that uses `FileManager` is `GTDServices/UndoJournal.swift`,
`GTDServices/Housekeeping.swift` and `FeatureReview/ReviewStateStore.swift` — all three write
**device-local state into Application Support**, never the vault, which is exactly what
ARCHITECTURE §3 prescribes — plus `GTDFixtures/SampleVault.swift`, which copies the bundled
fixture. Nothing hard-deletes: `VaultFileSystem` has no delete member at all, and no test or
source anywhere names `iCloud~md~obsidian`.

### Deliverable 4 — STYLEGUIDE §9 audit and the duplication cleanup

- **No literals in feature code.** `Feature*` and `App/` contain no literal colour, font,
  padding, radius, duration or symbol name at all — the last three (`chevron.up/.down`,
  `.caption`, `.title2`) became `DesignSystem` tokens. Verified by grep, not by eye.
- **No lying defaults.** Every form was walked. No pre-selected chip, no pre-filled date. The
  two proposals (+7 d follow-up, last-used knowledge folder) are UI state and reach no command
  until confirmed. The one pre-filled value in the app — `RoutineTimeRow`'s 07:00 — appears only
  *after* the person turns the toggle on, which is the confirmation, and is documented as such.
- **Signal colour always with a symbol or text**: enforced in one place
  (`DesignSystem.SignalPresentation`) and unit-tested per §2.2 row.
- One deviation left open: `RewardMoment` uses `.font(.system(size: 56))`, which §2.3 forbids.
  `TEST-INSTRUCTIONS.md` "Unresolved" #1.
- `Symbols.checkboxOn/Off` and `moveUp/moveDown` have no row in §7's icon map; the map is a vault
  note no agent can edit ("Unresolved" #3).
- Duplication cleanup done: the inbox-zero reward moment (bug #11) and the
  `"14 processed · 6 min"` wording. **Not done, on purpose:** `InboxSessionView` still implements
  the card drag geometry and fly-out itself instead of `DesignSystem`'s `CardFilingController` +
  `.cardSwipeFiling`. Rewriting a gesture in two files that have never been compiled is not
  low-risk, and `CardTarget`/`KeyMap`/`DragResolver` (the GTD semantics, unit-tested) stay in
  `FeatureInbox` either way. Note in `agent_task/ORCHESTRATOR-NOTES.md`.

### Deliverable 8 — docs drift found (T42's input)

Fixed in place where the fix was one line and the statement was untrue (CLAUDE.md's file list and
command list, README's doc map and layout, the `GTDVault` / `GTDModel` / `GTDServices` /
`DesignSystem` / `FeatureNext` module READMEs, and two doc comments that described behaviour the
code did not have — `RoutineHeatmap`'s "each cell's accessibility value" and `runHousekeeping`'s
"logged as an issue"). Left for T42:

- `docs/ARCHITECTURE.md` §4 still lists frozen Swift signatures that the code has moved past in
  small ways (T41-1/-2/-3 are additive, so nothing there is *wrong*, but the section is a
  duplicate of the source and will go stale — T42's deliverable 2 already plans to replace it).
- CLAUDE.md is 95 lines against its own "< ~80" rule. T41 removed nothing and added two lines;
  trimming it is T42's job.
- `docs/TRACEABILITY.md`'s "Follow-ups" table and every **partial** row are the input for
  `docs/KNOWN_ISSUES.md` (T42 deliverable 4).
- The six new briefs `50`–`55` must **not** be archived with the rest of `agent_task/`: they are
  work that has not happened yet.

### Files unverified on Linux

Everything under `#if canImport(SwiftUI)` that T41 touched, across all three passes:
`App/GTDApp.swift`, `App/PhoneShell.swift`, `App/AppComposition.swift`,
`DesignSystem/Tokens/Colors.swift`, `DesignSystem/Tokens/Typography.swift`,
`DesignSystem/Symbols.swift`, `DesignSystem/Copy.swift` (the SwiftUI-free half is compiled and
tested), `DesignSystem/Components/RewardMoment.swift`, `DesignSystem/Components/Rows.swift`,
`DesignSystem/Components/ReviewPieces.swift`, `FeatureInbox/InboxProcessingView.swift`,
`FeatureNext/NextView.swift`, `FeatureOverview/OverviewView.swift`,
`FeatureOverview/ActionListView.swift`, `FeatureProjects/ProjectViews.swift`,
`FeatureReview/ReviewViews.swift`, `FeatureRoutines/RoutineViews.swift`,
`FeatureWaiting/WaitingViews.swift`.

The pass-3 additions to that list are small and of one kind — three `@ScaledMetric` properties,
four accessibility modifiers and one context-menu `Button` — but `@ScaledMetric` had not been
used anywhere in this repo before, so it is called out separately in `TEST-INSTRUCTIONS.md`.

Everything else changed here (`GTDModel`, `GTDMarkdown`, `GTDAppCore`, `GTDVault`, `GTDServices`,
`DesignSystem/Components/HeatmapContent.swift`, `FeatureReview/ReviewSession.swift`,
`FeatureInbox/InboxCopy.swift` and all tests) builds and runs on Linux.

`TEST-INSTRUCTIONS.md` carries **"Where to look first (T41 blind review)"** — the nine API and
concurrency spots most likely to break under the real compiler, in the order worth trying, plus
the seven behaviours changed blind that must be checked in the running app — and an
**"Unresolved"** section with the judgement calls that need a Mac or the user, now including the
three known gaps that already have briefs so nobody files them as bugs.

### `scripts/benchmark.sh` (debug build, Linux container, 1 000 action notes / 1 084 files)

```
 cold scan — 1084 files on disk (PlainFileSystem)
   cold scan: 914.32 ms
   reads: 1084
   refresh, nothing changed: 239.74 ms
   refresh, one file changed: 240.12 ms
   reads: 1
 one command — 1084-file vault (InMemoryFileSystem)
   activate + first scan: 748.58 ms
   setStatus(.maybe): 280.16 ms
   writes: 1
   reads (the re-index that follows): 3
   undo: 134.33 ms
 derived queries — 1000 actions, 40 projects
   Rules.sidebarCounts: 2.03 ms      Rules.nextList: 1.97 ms
   Rules.waitingList: 1.14 ms        Rules.deferredList: 0.73 ms
   Rules.projectRows: 1.06 ms        Rules.stalledProjects: 0.57 ms
   Rules.timeline(±90 d): 1.74 ms
   projectRows, 40 projects: 0.89    projectRows, 80 projects: 1.32
 codec — 1000 action notes
   decode: 554.93 ms
   encode (unchanged, patching path): 996.34 ms
   encode (one field changed): 1038.02 ms
```

At 3 000 notes everything above scales linearly (`scripts/benchmark.sh 3000`): cold scan
2 704 ms, one command 749 ms, `projectRows` 3.2 ms. A debug build on a shared container is not a
phone — treat these as an upper bound and as something to compare a later run against.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
[11 expected "no rule to process file … xcstrings/assetcatalog" warnings]
Build complete!

=== swift test (Packages/GTDKit)
✔ 851 tests across all 18 test targets passed
  (GTDModelTests 134, GTDMarkdownTests 115, GTDVaultTests 112, FeatureReviewTests 77,
   FeatureProjectsTests 59, GTDServicesTests 54, FeatureInboxTests 49, FeatureOverviewTests 39,
   GTDStatsTests 32, FeatureSettingsTests 30, GTDNotificationsTests 27, DesignSystemTests 26,
   FeatureNextTests 24, GTDIntentsTests 22, FeatureWaitingTests 19, FeatureRoutinesTests 15,
   GTDAppCoreTests 11, GTDFixturesTests 6)

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```

(exit 0.)
