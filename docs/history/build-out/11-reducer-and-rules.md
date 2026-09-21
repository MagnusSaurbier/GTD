# T11 — Reducer & rules (`GTDModel`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Medium–hard · **Recommended model:** Opus

Pure functions and table-driven tests make it *look* Sonnet-sized, but this is the single definition of GTD semantics with many interacting rules (cap × project status × waiting × defer × promotion × undo-ability). The failure mode is omission — a rule quietly not enforced — which tests written by the same agent won't catch. Wants the more careful reader of the requirements.

## Goal

Make `Reducer.reduce` and `Rules` the complete, tested definition of GTD semantics. Pure Swift,
no I/O, no UI.

## Requirements covered

I4, I5, A2, A3, A5, P3, P4, P5, W1, W2, D1, E1, E2, E3 (counts), R6, N6 (what is undoable).

## Owns

`Sources/GTDModel/Reducer/`, `Sources/GTDModel/Rules/`, `Tests/GTDModelTests/`.
Type definitions elsewhere in `GTDModel` are frozen (contract change procedure applies).

## Deliverables

**Reducer** — for every `GTDCommand`: validation, state change, prompts, `extraOps`.
- Cap: moving/creating into `next` or `in-progress` fails with `.nextCapReached` when
  `Rules.countsTowardCap` ≥ `config.nextCap`. Actions of non-active projects can't enter Next (P3):
  `.invalid`.
- `updateProject` with a status leaving `active` demotes that project's `next`/`in-progress` actions to `backlog` (P3).
- `setRoutineTime` updates the routine's `time`.
- `waiting` requires `WaitingInfo` (W1). Leaving `waiting` clears `waitingFor`/`followUpDate`.
- `complete`: `status = done`, `completedDate = now`; if the action has a project → append a dated
  log entry to the project, tick the promoted step, emit `.whatsNext` (P5).
- A2 is a query, not a prompt: `Rules.suggestsProject(_ action:)` is true at ≥ 2 checkboxes; views show the inline button.
- `fileInbox`: all five `InboxDecision`s; unique filenames (title sanitising for the file system,
  collision → `.titleCollision`); knowledge + trash via `extraOps` moves; `created` carried over.
- `deferInboxToReview` sets `reviewReason`; such items leave the processing queue.
- `convertActionToProject`, `createProject` (optionally creating the area), `promoteStep`
  (creates the action linked to the project, marks the step `promotedTo`).
- `archiveCompleted`: done/trash actions with `completedDate` older than 30 days → move op to `Archive/YYYY/MM/`.
- `logRoutineStep` appends to the device's own log for `env.today`; re-logging a step replaces the earlier entry.
- `saveWeeklyReview` → `extraOps.put` at `GTD/Reviews/<yyyy>/KW <ww>.md` (text comes from a closure/encoder injected via `ReducerEnv` or is left to T16 — decide and document).

**Rules** (pure queries over `VaultSnapshot`):
`inboxQueue` (LIFO, excludes deferred-to-review), `reviewDeferredInbox`, `visibleActions(today:)`
(defer hidden until date), `nextList(contexts:timeAvailable:today:)` (in-progress first, ≤ cap,
plus chase items), `onTheGoNextList`, `chaseItems` (waiting with `followUpDate ≤ today`),
`waitingList` sorted by staleness, `deferredList`, `dueBadge`, `returnedFromDeferBadge`,
`stalledProjects` (active, zero open actions), `projectRows` (active actions, remaining steps),
`sidebarCounts`, `countsTowardCap`, `StalenessPolicy` (14 d / 30 d / inbox 7 d, one struct) and
`signals(for:today:) -> [Signal]` implementing every row of STYLEGUIDE §2.2 as semantic values (no strings, no colours), `archiveCandidates`, `timeline(from:to:)` for the calendar strip (D3).

## Acceptance

- Table-driven tests per command incl. every error path; rules tested against `GTDFixtures.sampleSnapshot` and edge cases (cap exactly reached, defer = today, follow-up today, project turning stalled on completion).
- Reducer is deterministic: same input + env ⇒ equal `Reduction`.
- A doc comment on each rule names the requirement ID it implements.
- `scripts/check.sh` passes; `InMemoryBackend`-based tests from T00 still pass.

## Contract changes

Additions only — no signature in ARCHITECTURE §4 was removed or renamed. Recorded in
`docs/ARCHITECTURE.md` §4 and §6.

| # | Change | Where | Why |
| --- | --- | --- | --- |
| T11-1 | Queries that convert a `Date` into a `Day` gained a trailing `calendar: Calendar = .current` parameter (`signals(for:)`, `archiveCandidates`, `closedDay`, `waitingSince`). | §4 | Otherwise a result depends on the machine's time zone; the reducer now passes `env.calendar`. Defaulted, so no call site changed. |
| T11-2 | `Rules` gained `isVisible`, `openActions(of:in:today:)`, `closedDay`, `waitingSince`, `isUndoable`. | §4 | Rules the brief names but had no query for; `isUndoable` is the single definition of N6 (see below). |
| T11-3 | Decision rows added to §6: defer × Next, "open action" for stalled, project rename, turn-into-project, Next list order. | §6 | Judgment calls the requirements left open; recorded rather than hidden in code. |
| T11-4 | `updateProject` refuses a changed `title` or `area` with `.invalid`. | §6 | A project's folder is its identity; a rename is a folder move (T16 work) and silently accepting it would make `title` and path disagree. **T22 must not offer a rename field in v1.** |
| T11-5 | `Rules.isUndoable(_:)` added; `GTDAppCore.InMemoryBackend` still has T00's private copy. | §4 | N6 must have one definition. **T16 should call `Rules.isUndoable` from `UndoJournal`, and T41 should delete the copy in `InMemoryBackend`.** The two agree today (there is a table test for the `Rules` one). |

## Result

**Status: done.** `scripts/check.sh` passes; 178 tests run (134 of them in `GTDModelTests`).

### What was built

- **`Reducer`** rewritten from T00's naive version into the complete definition of the GTD
  semantics. Its doc comment carries a rule → code table. Every command validates, mutates,
  prompts and emits `extraOps`; all `// T11:` markers are gone. Beyond T00's behaviour:
  completion effects (project log, step tick, `.whatsNext`) now fire on **every** path into
  `done` (`complete`, `setStatus`, `updateAction`) and are idempotent; closing an action always
  sets a closing date and re-opening clears it; renaming an action rewrites `ProjectStep.promotedTo`;
  `promoteStep` refuses done/already-promoted steps and falls back to the step's own wording;
  `convertActionToProject` emits `.whatsNext` so the new project is not born stalled;
  `updateProject` demotes whenever the new status is not `active`; contexts are validated against
  the closed list (A4) with migrated values grandfathered; titles must survive sanitising;
  `updateConfig` and `saveWeeklyReview` are validated; `archiveCompleted` uses `env.calendar`.
- **`Rules`** hardened: every list has a total order (no reliance on sort stability), `signals`
  is deterministic, `stalledProjects` uses an explicit "open action" definition, `waitingList`
  and `chaseItems` respect defer, `sidebarCounts` matches the lists its rows open,
  `archiveCandidates` falls back to the file modification date. Every query's doc comment names
  its requirement ID.
- **Tests** (`Tests/GTDModelTests`): `TestVault` (tiny hand-built snapshots), `ReducerInboxTests`
  (I1/I4/I5, all five decisions plus every refusal), `ReducerActionTests` (A1–A5, W1, D1, the
  11-row cap table, completion), `ReducerProjectTests` (P1–P5), `ReducerSystemTests` (R5/R6,
  config, weekly review, archive, N6, determinism), `RulesTests` + `SignalRuleTests` (every row
  and every threshold boundary of STYLEGUIDE §2.2). The existing `ReducerSmokeTests`,
  `GTDAppCoreTests` and `GTDFixturesTests` are unchanged and green.
- Sanity-checked by mutation: disabling the cap check fails 26 tests, disabling the P3 demotion
  or the waiting-clearing rule fails the tests that name them.

### Deviations and judgment calls

- `nextList` is **not** truncated to the cap. Truncating would hide exactly the items the user
  must demote to get back under it; `capSignal` shows `17/15` instead (STYLEGUIDE §2.2).
- A future defer date on a `next`/`in-progress` action is refused instead of silently demoting
  (ARCHITECTURE §6). This keeps `countsTowardCap` == `nextList().count` and the sidebar count
  == the cap badge in every vault the app has written.
- Filing a card to an *existing* project with zero actions is refused: the capture file is
  trashed by that decision, so it must produce at least one note.
- `saveWeeklyReview` stays as T00-4 decided — the reducer stores `snapshot.lastReview` and emits
  no `extraOps`; `GTDServices` writes the `KW` note. `GTDModel` never produces markdown.
- STYLEGUIDE §3.6's "Next/Backlog require a non-empty `What?`" is deliberately **not** in the
  reducer: it is card-level validation (shake + focus, no alert) and belongs to T20. The reducer
  does require a non-empty title, because the title is the file name.

### Open issues for later tasks

- **T16:** `GTD/Trash/<file>` and `Archive/YYYY/MM/<file>` keep the source file name — uniquify
  on collision. Use `Rules.isUndoable` for the undo journal. `extraOps` owns every path it names.
- **T22:** no project rename in v1 (T11-4). Use `demotionCount` before a status change; the
  reducer demotes `next`/`in-progress` to `backlog`.
- **T41:** delete `InMemoryBackend`'s private `isUndoable` copy in favour of `Rules.isUndoable`.

### Files that could not be compiled on Linux

None — `GTDModel` is Foundation-only and fully covered by `swift test` on Linux. No SwiftUI,
no platform guards, nothing written blind.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete! (2.39 secs)
=== swift test (Packages/GTDKit)
Build complete! (5.03 secs)
… 18 test-target runs, all green; 178 tests, 134 of them in GTDModelTests:
  ✔ Test run with 134 tests in 8 suites passed after 0.019 seconds.
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok
=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's
build system only — verify this step on a Mac.
=== check.sh finished
```

(exit 0. The full log is 714 lines of per-test output; the 11 `no rule to process file …
xcstrings/assetcatalog` warnings are the expected ones from T00.)
