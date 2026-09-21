# T23 — Waiting-for, deferred, calendar strip (`FeatureWaiting`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

Two straightforward lists plus one custom view (`CalendarStrip`). Date bucketing comes from `Rules.timeline`; the strip is layout work with cosmetic failure modes.

## Goal

Everything driven by dates: the waiting list, the deferred list, and the Mac timeline strip.

## Requirements covered

§7: W1, W2, D1, D3.

## Owns

`Sources/FeatureWaiting/`, `Tests/FeatureWaitingTests/`.

## Public API

```swift
public struct WaitingView: View { public init(onOpen: @escaping (NoteID) -> Void) }
public struct DeferredView: View { public init(onOpen: @escaping (NoteID) -> Void) }
public struct CalendarStrip: View { public init(days: Int = 14, onOpen: @escaping (NoteID) -> Void) }   // Mac
```

## Deliverables

- **WaitingView:** columns what · who · waiting since N days · follow-up date; sorted by staleness
  (`Rules.waitingList`); overdue highlighted. Row actions: *chase done → bump* (`DateValueChip`, +7 d offered as a suggested chip), *resolved → back to Next/Backlog* or *done*, edit who.
- **DeferredView:** deferred actions grouped by return date (this week / later), action: un-defer now, change date.
- **CalendarStrip (D3):** per STYLEGUIDE §3.10 — 14-day strip, up to 3 markers per day distinguished by **symbol** (not hue), signal colour only when §2.2 says so, accent underline for today; data from `Rules.timeline`; today anchored; hover/tap shows the items; overdue pile on the left edge.
- Uses `DesignSystem.WaitingInfoSheet` for editing who/follow-up; contributes "recent who" suggestions to it as ghost chips (suggestion styling per §1) via its public parameters — coordinate through T12's API, additions only.

## Acceptance

- Unit tests: staleness ordering, grouping, timeline bucketing across month/year boundaries.
- Previews for each view incl. empty states.
- `scripts/check.sh` passes.

## Result

**Status: done.**

### What was built

- `WaitingListModel` (Linux-testable, no SwiftUI) extended beyond T00's shell: `isOverdue(_:)`,
  `waitingInfo(for:)`, `suggestedBump`, `bumped(_:to:)` (back "chase done → bump" and "edit who"),
  `unDeferred(_:)`/`redeferred(_:to:)` (back "un-defer now"/"change date"), and
  `signalStep(for:policy:)`, which maps a `Rules.TimelineEntry` to the `SignalStep` its calendar
  marker should be tinted with (STYLEGUIDE §3.10: coloured only where §2.2 defines a signal;
  `deferred` markers are never tinted — the only defer-related signal, `back`, is itself neutral).
  Fixed `waitingSinceDays` to use `Action.modified` (falling back to `created`) instead of
  `created` alone, matching ARCHITECTURE §5's definition of "untouched".
- `WaitingView`: real rows (what · who · waiting-since · follow-up `DateValueChip` + badges),
  sorted by `Rules.waitingList` (staleness). Row actions: swipe trailing = Done, swipe leading =
  Backlog; context menu adds "Bump follow-up" (swaps the follow-up chip to the suggested +7 d
  until a date is confirmed — nothing is written until then), "Next"/"Backlog"/"Done" (resolved),
  and "Edit who" (opens `WaitingInfoSheet(suggestedWho: recentWho)`, unchanged public API — no
  DesignSystem edit needed, `suggestedWho` was already there).
- `DeferredView`: sections "This week"/"Later" from `WaitingListModel`, each row with badges and
  a `DateValueChip` bound to `deferDate` ("change date"); swipe/context-menu "Un-defer now" clears
  the date via `.updateAction`.
- `CalendarStrip`: 14-day strip (`Rules.timeline`), up to 3 markers/day + overflow count, an
  "Overdue" pile column (`WaitingListModel.overduePile`) on the leading edge, today's column
  underlined in accent, markers tinted via `signalStep(for:)`, `.help()` tooltip + tap-to-open per
  marker.
- `FeatureWaitingTests` (19 tests, replacing T00's placeholder): staleness ordering, defer
  grouping (this-week/later boundary and exclusion of not-yet-returned/undeferred items), timeline
  bucketing across a month boundary (Jan→Feb) and a year boundary (2026→2027), overdue-pile
  membership and kind, the signal-step mapping for due/follow-up/deferred markers, waiting-since
  (modified vs. created), bump/edit-who helpers, recent-who dedupe/cap, and badge delegation —
  all against hand-built `VaultSnapshot`s with a fixed `today`, not only `GTDFixtures`.

### Deviations / judgement calls

- "Waiting since N days" uses `Action.modified` (file mtime), not `created`: the model has no
  separate "entered waiting" timestamp, and ARCHITECTURE §5 already defines "untouched" this way.
- "Chase done → bump" is implemented as a context-menu action that puts the row's own follow-up
  chip into a locally-suggested (+7 d, dashed) state rather than adding a second chip; picking any
  date in its picker confirms the bump. No DesignSystem change was needed or made.
- Feature-local strings not in STYLEGUIDE §6.2/§6.3 ("This week", "Later", "Overdue", "Bump
  follow-up", "Edit who", "Un-defer now") are plain literals in this target's own
  `Resources/Localizable.xcstrings` catalog, per ARCHITECTURE §5 ("every UI target owns its own
  catalog… parallel tasks never share one"); `DesignSystem.Copy`/`Package.swift` were not touched.
- No light/dark/AX1 preview variants were added (only one preview per state, matching every other
  Wave-1 Feature target's current baseline); STYLEGUIDE itself treats that matrix as T12 follow-up
  work (its own `DesignSystem` components don't have them yet either).
- No new Mac keyboard shortcuts for bump/edit-who/un-defer: STYLEGUIDE §4.5's shortcut map doesn't
  name any for this feature, and none for a specific Feature target's row actions have been
  invented elsewhere in the codebase either; the context menu is reachable via Full Keyboard
  Access / VoiceOver rotor instead.

### Files unverified on Linux (blind SwiftUI, verify on a Mac)

`Packages/GTDKit/Sources/FeatureWaiting/WaitingViews.swift` — all of it (only Foundation
`.swift build`-parsed here). Specifically worth checking on a Mac: `.swipeActions` stacked with
`.contextMenu` on the same row (`WaitingRow`, `DeferredRow`), the `DateValueChip` binding trick
that shows the row's own chip as "suggested" while `offeringBump` is true, and the
`CalendarStrip` column layout (`HStack` of `.frame(maxWidth: .infinity)` columns plus the
conditional overdue column) at narrow/AX-large widths.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
Build complete!

=== swift test (Packages/GTDKit)
... (all suites) ...
✔ Suite FeatureWaitingTests passed after 0.010 seconds.
✔ Test run with 19 tests in 1 suite passed after 0.010 seconds.
... (all other suites pass) ...

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
Exit code 0.
