# T14 — Weekly stats & routine audit (`GTDStats`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

Pure aggregation over value types, no concurrency, no I/O, no UI. ISO-week edge cases are the only trap and they are called out in the acceptance tests.

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

**Status: done.**

### What was built

- `WeeklyStats.compute(snapshot:week:calendar:)` — captured/processed (see approximation note
  below), done this week, Next age distribution (median + 3 oldest `NoteID`s, via
  `Rules.visibleActions` filtered to `countsTowardCap`), actions untouched > 30 days (reuses
  `StalenessPolicy.default.actionAttentionDays` so it agrees with the `untouched` signal),
  waiting items by age (`modified` falling back to `created`), stalled project count (via
  `Rules.stalledProjects`). All "today"-relative numbers are anchored on **`week`'s last day**
  (its Sunday), not a real current day, since the signature takes no `today` — documented on the
  method.
- `RoutineAudit.compute(routines:log:endingOn:)` — 7-day × steps grid ending on `endingOn`,
  per-step and per-routine completion %, trend vs. the prior 7 days. Rows are built from the
  routine's *current* `steps`, so a dropped template step silently gets no row and a new one
  just shows "not logged" for days before it existed — no special-casing needed. Multi-device
  merge: the log entry with the latest `at` wins per (day, step).
- Kept `ISOWeek` and `Day.isoWeek`/`Day.startOfISOWeek` from T00 as-is — the integer-arithmetic
  algorithm is correct; added `ISOWeekTests` covering the classic year-boundary cases (a 53-week
  year, a late-December date already in next year's week 1, `.previous` crossing the boundary)
  to prove it rather than just trust it.
- New test files: `ISOWeekTests.swift`, `WeeklyStatsTests.swift` (one synthetic snapshot per
  field, hand-built with a fixed-UTC injected `Calendar`, never `.current`),
  `RoutineAuditTests.swift` (grid shape, skipped-vs-done, template drift both directions,
  multi-device merge, trend, empty data), `FixturesSmokeTests.swift` (both `compute`s over
  `GTDFixtures.sampleSnapshot` — sanity only, not a source of truth for exact numbers). Removed
  `GTDStatsPlaceholderTests.swift` (superseded).

### The captured/processed approximation (documented in the doc comment on `compute`)

The vault has no persisted "filed at" timestamp — only `created` (which survives from the inbox
item onto the `Action` it becomes) and whether something is still an `InboxItem` right now. So:
**captured** = inbox items still queued with `created` in `week`, plus actions with `created` in
`week`; **processed** = the actions half of that same count (the ones that already left the
inbox). This undercounts anything filed to `Knowledge`/trash or into a brand-new project with no
initial actions (`Project` has no `created` field at all — ARCHITECTURE §4), and it cannot
distinguish "captured earlier, processed this week" from "captured this week, still queued" — a
review commonly does the former for everything piled up in the inbox, and there is no signal in
the snapshot to detect it. Good enough for a "does the inbox move" gut check, not an audit trail.
Flagging this for whoever wires up T27: if it reads wrong in practice, the fix needs a persisted
filed-at log, which is out of GTDStats's pure/snapshot-only scope (ARCHITECTURE §6 decision).

### Deviations from the brief

None — kept the exact `compute` signatures T00 stubbed. No new parameters, no threshold added to
the public API (the 30-day untouched threshold reuses the existing `StalenessPolicy.default`
rather than being hard-coded again).

### Contract changes

None. No shared files touched beyond this task doc and the module README.

### Files unverified on Linux

None — `GTDStats` and `GTDStatsTests` are both Foundation-only (ARCHITECTURE §5); everything
here compiled and ran under plain `swift test` on Linux.

### Gotchas for later tasks (T27 in particular)

- `WeeklyStats.compute`/`RoutineAudit.compute` take no `today` — every staleness/age number is
  relative to the **end of the requested week**, not "right now". If the review wizard wants
  live numbers as the reviewer sees them mid-review, pass `ISOWeek(containing: Day.today())`.
- `RoutineAudit.compute(endingOn:)` is *not* week-aligned — it's a rolling 7 days ending on
  whatever `Day` you pass, independent of `ISOWeek`. For §10.3's "this week" framing, pass the
  same review day used for `WeeklyStats`.

### `scripts/check.sh` (tail)

```
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
Full `swift test` run (all targets) passed, including the new `GTDStatsTests` (32 tests across
`ISOWeekTests`, `WeeklyStatsTests`, `RoutineAuditTests`, `FixturesSmokeTests`), exit code 0.
