# FeatureRoutines

Routines: one step per screen, done/skip, resume from today's log (R1–R6).

## Public API

- `RoutinesHomeView()` — one row per routine (icon, time, today's state); tapping one presents
  `RoutineRunnerView` (`fullScreenCover` on iOS, `sheet` on Mac).
- `RoutineRunnerView(routine:onFinished:)` — one step per screen: `ItemCard` with the step title,
  sub-steps as a local tappable checklist (never logged; a journaling step with none shows "On
  the reMarkable" instead), `GlassActionBar` with `Skip`/`Done` each filling half the bar (min height 56; Mac `S`/`⏎`),
  a `Back` button once there is a step to go back to (`RoutineRun.canGoBack`), and a toolbar
  `Close` that leaves the run. Horizontal swipe back is the only gesture — no swipe filing. Finishing shows the STYLEGUIDE §5 reward screen.
- `RoutineRun` (`@MainActor @Observable`, Linux-compilable, unit-tested): resumes at the first
  step with no log entry for today, **advances on the tap** and logs via `GTDCommand.logRoutineStep` behind it (the vault write
  takes about a second on a phone; a failed one returns the run to that step and reaches the
  shell's alert through `AppModel.perform`; taps not yet written already count in the summary), `back()`
  rewinds so re-logging replaces the earlier entry (reducer dedupes by day/routine/step/device),
  tracks every day it has written to so a run left open across midnight still counts correctly
  (each entry keeps its own real day — R5 is untouched).
- `RoutineProgress.today(routine:log:today:)` → `.notStarted` / `.inProgress(completed:total:)` /
  `.finished` + `.homeText`, built on the same `RoutineRun.resumeIndex` a run itself uses.
- `RoutineStep.isJournaling`: best-effort keyword match (dream/achievement/gratitude/
  will-do-better/journal); there is no model flag (ARCHITECTURE §3 dropped `journalSteps`), and
  R4 (no text input) holds regardless of the match — it only picks the meta line shown.

## Platform guards (ARCHITECTURE §5)

`RoutineViews.swift` is wrapped entirely in `#if canImport(SwiftUI)`, so on Linux it is not
compiled at all — `swift build`/`swift test` never type-check it; it is **unverified**, build it
on a Mac (`scripts/check.sh --app`) before trusting it. `RoutineRun.swift` has no SwiftUI import
and is fully covered by `swift test`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureRoutinesTests` — 17 tests: resume logic
(fresh/partial/complete/template-changed, both a removed and an inserted step), `RoutineProgress`
mapping, the journaling heuristic, and `RoutineRun` against `AppModel` + `InMemoryBackend`:
resume-from-scratch, advancing before the write lands (a gated backend), re-log after going back, finish + done/skipped counts, resume mid-session, a
failed log leaving the step in place (a custom always-failing `GTDBackend` — there is no command
to edit a routine's steps to trigger this live), and a day rollover mid-run.
