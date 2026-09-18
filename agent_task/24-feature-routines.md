# T24 — Routines (`FeatureRoutines`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

Small, linear state machine (`RoutineRun`) with clear tests and a simple card UI. The midnight-rollover and template-changed cases are listed explicitly.

## Goal

Step-by-step routine runner, primarily for iPhone.

## Requirements covered

§9: R1, R2, R4, R5, R6 (R3 scheduling is T13/T40; this task provides the entry point).

## Owns

`Sources/FeatureRoutines/`, `Tests/FeatureRoutinesTests/`.

## Public API

```swift
public struct RoutinesHomeView: View { public init() }                       // buttons per routine + today's progress
public struct RoutineRunnerView: View { public init(routine: NoteID, onFinished: @escaping () -> Void) }
```

## Deliverables

- `RoutineRun` (`@Observable`, unit-tested): steps from the template, today's log → resume at the
  first unlogged step; done / skip per step → `GTDCommand.logRoutineStep`; going back re-logs
  (reducer replaces the entry); finishing shows a summary (done x / skipped y).
- Runner UI: one step per screen, large title, sub-steps inline as a tappable local checklist
  (sub-steps are not logged), `GlassActionBar` with `Skip` / `Done` (STYLEGUIDE §3.7), **no swipe filing** — horizontal swipe back = previous step only; Journaling steps are plain done/skip — **no text input** (R4).
- Home: one big button per routine with its scheduled time and today's state (not started /
  3 of 8 / finished), so it can be the landing view for the routine notification deep link.
- Template edits in Obsidian mid-day are tolerated (step ids = slugs; unknown logged steps ignored).
- Mac: same views, keyboard `⏎` done, `S` skip.
- Routines never produce actions and never appear in action lists (R6) — nothing to build, just don't.

## Acceptance

- Unit tests: resume logic, re-log, template change tolerance, day rollover at midnight while a run is open.
- Previews: home, runner (step with sub-steps, last step, summary).
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
