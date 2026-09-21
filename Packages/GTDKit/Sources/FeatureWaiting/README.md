# FeatureWaiting

Waiting-for, deferred items and the Mac calendar strip (W2, D1, D3).

## Public API

`WaitingView(selection:onOpen:)`, `DeferredView(selection:onOpen:)`, `CalendarStrip(days:onOpen:)`.

On macOS both lists are stock selectable `List`s (M2, the same shape as
`FeatureOverview.ActionListView`): a click or the arrow keys select a row, selecting *is* opening
(`onOpen`), and `selection` — the note the detail column shows — is what the list highlights. The
lists keep no selection of their own. On iOS the rows stay tap-to-open. `WaitingCopy` (no SwiftUI)
holds the one string these views need that `DesignSystem.Copy` does not carry in the right form:
the deferred screen is titled **"Deferred"**, the section's name, not `Copy.deferLabel`
("Defer"), which is the date chip's field label.

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
  are never tinted). `followUpSignal(for:)` — the `chase` signal's step, which tints the row's
  follow-up date chip once the date has passed. `badges(for:)`, `recentWho` (deduped, capped at 5, for
  `WaitingInfoSheet(suggestedWho:)`).
- `metaParts(for:)` (T11, W1/D39) — the row's meta line as parts: `who` first when present, then
  the "waiting since" age — `who` is simply omitted when it is empty/nil, never printed as a
  dangling "— " (§1 "no lying defaults"). Pure (`WaitingListModel.rowMeta(who:ageText:)`), tested
  for both branches without SwiftUI; `WaitingRow` renders it with `Copy.metaLine(_:)`.

## Invariants

- Every row command goes through `AppModel.perform(_:)`, never `try? await model.send(…)`.
  "Move to Next" can be refused by the Next cap and un-deferring by the defer × Next rule
  (ARCHITECTURE §6); both used to fail silently. The refusal now lands in
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

`cd Packages/GTDKit && swift test --filter FeatureWaitingTests` — 23 tests.
