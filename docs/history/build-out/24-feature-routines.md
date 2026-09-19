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

**Status: done.** `scripts/check.sh` passes (pasted below).

### What was built

- `RoutineRun` (`Sources/FeatureRoutines/RoutineRun.swift`, Linux-compilable, `@MainActor
  @Observable`): rewritten from T00's compiling shell. Resumes at the first step with no log
  entry for today (`resumeIndex`, a pure static func also used by `RoutineProgress`); `log(_:)`
  sends `GTDCommand.logRoutineStep` and only advances `index` if the write actually succeeds
  (T00's version used `try?` and always advanced — changed so a failed write, e.g. a step the
  live template no longer has, leaves the user on the same step instead of silently skipping
  it); `back()` rewinds locally so re-logging replaces the earlier entry (the reducer dedupes by
  day/routine/step/device — R5); tracks every calendar day it has written a log entry under
  (`sessionDays`), so `doneCount`/`skippedCount` stay correct for a run that is still open when
  midnight passes, even though each entry keeps the real day it happened on.
- `RoutineProgress` (same file): `.today(routine:log:today:)` → `.notStarted` /
  `.inProgress(completed:total:)` / `.finished`, plus `.homeText` ("Not started" / "3 of 8" /
  "Finished") for the home row — not in STYLEGUIDE §6.3's canonical table, so kept local to this
  target rather than added to `DesignSystem.Copy` (another target's public API, read-only here).
- `RoutineStep.isJournaling` (same file): keyword heuristic (dream/achievement/gratitude/
  will-do-better/journal) deciding whether an empty-substep step shows STYLEGUIDE §3.7's "On the
  reMarkable" meta line instead of nothing. There is no model flag for this by design
  (ARCHITECTURE §3: "`journalSteps` is not needed — all steps are done/skip only"); R4 (no text
  input, ever) holds regardless of whether the match is right.
- `RoutinesHomeView` / `RoutineRunnerView` (`RoutineViews.swift`, SwiftUI, compiled blind):
  rewritten from T00's shell, which recreated `RoutineRun` on every body evaluation (losing
  `back()` and any local state across re-renders) — now held in `@State`, created once via
  `.task`. Home is a `List` of big rows (icon, time, today's state) that present the runner via
  `fullScreenCover` (iOS) / `sheet` (Mac). Runner: `ItemCard` (progress text, step title,
  sub-steps as a local tappable checklist that is never logged, or the journaling meta line),
  horizontal swipe back only (no swipe filing — deliberately different from the inbox card),
  `GlassActionBar` `Skip`/`Done` with Mac `S`/`⏎` shortcuts; finishing shows the STYLEGUIDE §5
  reward screen with `Copy.stepsSummary` plus an explicit done/skipped breakdown (the brief asks
  for "done x / skipped y"). A toolbar `Done` lets the user leave early from any screen. Previews
  for home, runner (step with sub-steps, last step, journaling step, summary), most in light +
  dark, home + one runner state also at AX1.

### Deviations from the brief (all within FeatureRoutines, no contract changes)

- `RoutineRun.log` returns `false` and does not advance on a failed write, instead of the
  original shell's silent swallow-and-advance (see above).
- `RoutineRun.results()` dropped its `today:` parameter in favor of the `sessionDays` set — this
  type isn't part of any frozen contract (only the two views are, per the brief's Public API) and
  has no callers outside this target.
- Journaling-step detection uses a text heuristic, not a model field (none exists, by design).

### Unverified on Linux (SwiftUI — build on a Mac before trusting)

`Sources/FeatureRoutines/RoutineViews.swift` — entirely guarded by `#if canImport(SwiftUI)`, so
Linux does not even parse it; `swift build`/`swift test` never touch it. `RoutineRun.swift` has
no SwiftUI import and is fully covered by tests. Things to eyeball on a Mac: the `fullScreenCover`
vs `sheet` split, `.keyboardShortcut("s", modifiers: [])` / `.keyboardShortcut(.return, modifiers:
[])` (bare, no ⌘), the horizontal back-swipe gesture (60pt threshold — a guess, STYLEGUIDE gives
no number for this gesture, only for the inbox card's `DragThresholds`), and the multi-closure
`ContentUnavailableView(label:description:actions:)` on the summary screen.

### Gotchas for later agents

- T40 (app shell): `RoutinesHomeView` is meant to be the routine notification's deep-link
  landing view and the iPhone Routines tab content; it already handles start-a-routine itself, so
  the shell just needs to host it (per ARCHITECTURE §4.2, inside a `fullScreenCover`/tab, no
  extra wiring for the tap-to-start flow).
- The vault layout's one-log-file-per-day format means a routine's log entries keep the day they
  were actually logged on even if the run stays open across midnight; only the *open* run's own
  running total stays correct (via `sessionDays`) — a fresh run started after such a rollover
  reads only "today"'s file and may re-ask for a step that was actually completed the previous
  calendar day. This is a vault-format limitation, not a `RoutineRun` bug; documented here since
  nothing else records it.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete!

=== swift test (Packages/GTDKit)
Test run with 15 tests in 1 suite passed after 0.006 seconds.   (FeatureRoutinesTests)
... (all other targets' suites also passed — full run: no failures anywhere)

=== docs check
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's
build system only — verify this step on a Mac.

=== check.sh finished
```
