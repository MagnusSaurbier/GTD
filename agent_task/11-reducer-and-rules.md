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
- `toggleCheckbox`/`updateAction`: when the checkbox count goes from 1 to 2 → `.suggestTurnIntoProject` (A2).
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
`sidebarCounts`, `countsTowardCap`, `archiveCandidates`, `timeline(from:to:)` for the calendar strip (D3).

## Acceptance

- Table-driven tests per command incl. every error path; rules tested against `GTDFixtures.sampleSnapshot` and edge cases (cap exactly reached, defer = today, follow-up today, project turning stalled on completion).
- Reducer is deterministic: same input + env ⇒ equal `Reduction`.
- A doc comment on each rule names the requirement ID it implements.
- `scripts/check.sh` passes; `InMemoryBackend`-based tests from T00 still pass.

## Result

_(fill in when done)_
