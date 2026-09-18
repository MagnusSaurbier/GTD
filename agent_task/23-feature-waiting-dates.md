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
public struct CalendarStrip: View { public init(days: Int = 28, onOpen: @escaping (NoteID) -> Void) }   // Mac
```

## Deliverables

- **WaitingView:** columns what · who · waiting since N days · follow-up date; sorted by staleness
  (`Rules.waitingList`); overdue highlighted. Row actions: *chase done → bump* (+7 d default,
  `DateChip`), *resolved → back to Next/Backlog* or *done*, edit who.
- **DeferredView:** deferred actions grouped by return date (this week / later), action: un-defer now, change date.
- **CalendarStrip (D3):** horizontal timeline of days with three marker kinds — defer-returns,
  due, follow-ups — from `Rules.timeline`; today anchored; hover/tap shows the items; overdue pile on the left edge.
- Uses `GTDDesign.WaitingInfoSheet` for editing who/follow-up; contributes "recent who" suggestions to it as ghost chips (suggestion styling per §1) via its public parameters — coordinate through T12's API, additions only.

## Acceptance

- Unit tests: staleness ordering, grouping, timeline bucketing across month/year boundaries.
- Previews for each view incl. empty states.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
