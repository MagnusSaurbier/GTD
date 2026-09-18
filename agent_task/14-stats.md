# T14 — Weekly stats & routine audit (`GTDStats`)

**Wave 1 · needs T00**

## Goal

Pure computations behind step 3 of the weekly review. Nothing is persisted (ARCHITECTURE §6).

## Requirements covered

§10.3 (live stats, automatic routine audit), §1 staleness.

## Owns

`Sources/GTDStats/`, `Tests/GTDStatsTests/`.

## Deliverables

- `WeeklyStats.compute(snapshot:week:calendar:)`:
  captured vs processed this week (inbox files created vs. items that left the inbox — derive
  from `created` of actions/projects and remaining inbox; document the approximation),
  done this week, age distribution of Next items (median, oldest 3), actions untouched > 30 days
  (uses `Action.modified`), waiting items by age, stalled project count.
- `RoutineAudit.compute(routines:log:endingOn:)`: per routine a 7-day × steps grid
  (done / skipped / not logged), completion % per step and per routine, trend vs the previous 7 days.
  Steps that no longer exist in the template are dropped; new steps show "not logged".
- ISO week helpers (`KW` number, week interval, Monday start).
- Value types are `Sendable, Equatable` and ready to render (no formatting logic in views beyond strings).

## Acceptance

- Deterministic unit tests with synthetic snapshots incl. year boundary weeks (KW 52/53/1), multi-device log merging, empty data.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
