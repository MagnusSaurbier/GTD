# FeatureWaiting

Waiting-for, deferred items and the Mac calendar strip (W2, D1, D3). **Owned by T23.**

## Public API

`WaitingView(onOpen:)`, `DeferredView(onOpen:)`, `CalendarStrip(days:onOpen:)`.

`WaitingListModel(model:)` — Linux-compilable, `@MainActor @Observable`, no SwiftUI. Wraps
`Rules.waitingList`/`deferredList`/`timeline` for the three views:
- `waiting` (staleness order), `isOverdue(_:)`, `waitingSinceDays(_:)` (uses `Action.modified`,
  falling back to `created` — the app has no separate "entered waiting" timestamp).
- `waitingInfo(for:)`, `suggestedBump`, `bumped(_:to:)` — back the "chase done → bump" and
  "edit who" row actions (`WaitingInfoSheet`); nothing is written until the sheet or date picker
  is confirmed (STYLEGUIDE §1).
- `deferredThisWeek` / `deferredLater`, `unDeferred(_:)`, `redeferred(_:to:)` — back "un-defer
  now" / "change date" in `DeferredView`.
- `timeline(days:)`, `overduePile`, `signalStep(for:policy:)` — calendar-strip columns and the
  marker tint (STYLEGUIDE §3.10: coloured only where §2.2 defines a signal; `deferred` markers
  are never tinted). `badges(for:)`, `recentWho` (deduped, capped at 5, for
  `WaitingInfoSheet(suggestedWho:)`).

## Invariants

- Every row command goes through `AppModel.perform(_:)`, never `try? await model.send(…)`.
  "Move to Next" can be refused by the Next cap and un-deferring by the defer × Next rule
  (ARCHITECTURE §6); before T41 both silently did nothing. The refusal now lands in
  `AppModel.lastError` and the app shell shows it.

## Platform guards (ARCHITECTURE §5)

Views live in `WaitingViews.swift`, wrapped entirely in `#if canImport(SwiftUI)` — **unverified
on Linux, blind-written.** Row actions use only stock SwiftUI (`.swipeActions`, `.contextMenu`,
`.sheet(item:)`, `DateValueChip`'s own `.popover`); nothing beyond what `DesignSystem` and
`GTDAppCore` already export. Verify on a Mac: the two custom rows (`WaitingRow`, `DeferredRow`)
compile and look right, `CalendarStrip`'s `ScrollView`/column layout, and that `.swipeActions`
stacked with `.contextMenu` on the same row behaves as expected on both platforms.

All logic worth testing (staleness ordering, defer grouping, timeline bucketing across month/year
boundaries, overdue detection, the calendar-strip signal mapping, recent-who dedupe) lives in
`WaitingListModel` and is covered by `FeatureWaitingTests`, built against hand-built
`VaultSnapshot`s with a fixed `today` (not only `GTDFixtures.sampleSnapshot`, so date-boundary
cases are exact).

## Testing

`cd Packages/GTDKit && swift test --filter FeatureWaitingTests`
