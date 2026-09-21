# GTDStats

Weekly review numbers and the routine audit heatmap, computed on the fly from a snapshot — nothing
is persisted. Public types: `WeeklyStats`, `RoutineAudit` (+ `.Row`/`.Cell`), `ISOWeek`.

- `WeeklyStats.compute(snapshot:week:calendar:)` — captured/processed, done this week, Next age
  (median + 3 oldest `NoteID`s), actions untouched > 30 days, waiting items by age, stalled
  project count. All "today"-relative numbers are anchored on **`week`'s last day (its Sunday)**,
  not the real current day, so the function is pure in its parameters. Captured/processed is an
  approximation — see the doc comment on `compute` for exactly what it can and can't see (no
  filed-at timestamp exists anywhere in the vault; `Project` has no `created` field either).
- `RoutineAudit.compute(routines:log:endingOn:)` — one audit per routine: a 7-day × steps grid
  ending on and including `endingOn`, completion % per step and overall, trend vs. the prior 7
  days. Rows follow the **current** `Routine.steps`, so a dropped template step gets no row and a
  brand-new one just shows "not logged" for days before it existed — no special-casing. When two
  devices logged the same routine/step/day, the entry with the latest `at` wins.
- `ISOWeek` — `Day.isoWeek`/`Day.startOfISOWeek` (`GTDModel/Core/Day.swift`) do the actual
  Gregorian-integer math; `ISOWeek` is a thin, Codable-free wrapper (`year`, `week`, `monday`,
  `days`, `previous`). Verified against the classic year-boundary cases (a year with 53 ISO
  weeks, a late-December date that is already next year's week 1) in `ISOWeekTests`.

## Platform guards (ARCHITECTURE §5)

Foundation-only, no SwiftUI. `Calendar` is only used to turn a `Date` (`created`/`modified`/
`completedDate`) into a `Day`; callers must inject a fixed-time-zone one in tests (never
`.current`) for determinism — see `WeeklyStatsTests`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDStatsTests` — 33 tests. `ISOWeekTests` (year-boundary weeks),
`WeeklyStatsTests` (synthetic snapshots, one per field), `RoutineAuditTests` (grid shape, template
drift, multi-device merge, trend), `FixturesSmokeTests` (both `compute`s over
`GTDFixtures.sampleSnapshot`).
