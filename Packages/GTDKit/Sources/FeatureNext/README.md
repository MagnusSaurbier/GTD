# FeatureNext

The default screen: filter chips over a plain list of Next actions, plus a chase section for
overdue follow-ups (E1, E2, W2).

## Public API

- `NextView(mode:onOpen:onQuickCapture:)` — `onQuickCapture` is a new, optional (default `nil`)
  third parameter beyond the brief's original two: I7's "capture, then jump into processing of
  that one card" needs the app shell, since `FeatureNext` must not import `FeatureInbox`. `nil`
  just hides the quick-add button/`⌘N`, so existing two-argument call sites still compile.
- `NextViewMode { full, onTheGo }`.
- Linux-compilable: `NextListModel` (filtering, sections, cap, empty states, row commands),
  `NextFilterStore` (+ `UserDefaultsNextFilterStore`, `InMemoryNextFilterStore`).

## Behaviour

- Filter chips (context multi-select, time-available single-select via `TimeBucketChipGroup`,
  reusing its 10/30/60/90 buckets for "time I have" rather than "time this takes") persist per
  device through `NextFilterStore`, namespaced by `NextViewMode` so the Mac's full list and the
  iPhone's on-the-go list don't share filters. `.onTheGo`'s hard context restriction lives in
  `Rules.onTheGoNextList` itself — the chips just narrow within it.
- Chase section (overdue follow-ups) is unaffected by the filters; quick actions bump +7 d /
  resolved (= complete).
- Tick-off completes immediately; an undo toast (`AppModel.undoLabel`, auto-dismiss 5 s) covers
  it, independent of the backend's own single-level undo bookkeeping (`⌘Z` keeps working after
  the toast fades). Inline checkboxes for actions with ≥ 2 checkboxes; ticking every one *offers*
  to complete the action (a separate button) rather than doing it automatically.
- Row context menu (all rows) / iOS swipe (trailing `Done`, leading `Backlog`): done, start
  (→ in-progress), demote to Backlog, set waiting (`WaitingInfoSheet`), defer (`DateValueChip` in
  a small sheet). Every swipe action has a context-menu twin — the Mac has no swipes and
  VoiceOver cannot reach one (STYLEGUIDE §8).
- **Deferring a `next`/`in-progress` row demotes it to Backlog first, as its own
  explicit command** — the reducer refuses a future `deferDate` on a cap-counting action outright
  and never demotes for you (ARCHITECTURE §6); `NextListModel.setDefer` does the two-step itself.
- Every row command goes through a small `run(_:)` wrapper that turns a thrown `GTDError` into an
  alert instead of a silent `try?` (a refused command must
  reach the person).
- Cap indicator (STYLEGUIDE §2.2): plain count below the cap, `Badge` (`15/15`, overdue past it)
  at/above — never a meter.

## Contract-adjacent additions (recorded here, not a §4 contract change)

Added to `DesignSystem.Copy`: `start`, `resolved`, `quickCapture`, `actionFailed`,
`bumpFollowUp(days:)`. Added to `DesignSystem.Symbols`: `checkboxOn`/`checkboxOff` (SF Symbols
`checkmark.square`/`square` — STYLEGUIDE §7 has no checklist-row entry yet; flagged there as a
gap, not filled in the guide itself since it is a synced vault note).

## Platform guards (ARCHITECTURE §5)

`NextView.swift` is wrapped entirely in `#if canImport(SwiftUI)` and was written and reviewed
without a compiler — **unverified on Linux**, build it on a Mac (`scripts/check.sh --app`).
`NextListModel.swift` and `NextFilterStore.swift` have no SwiftUI import and are fully covered by
`swift test` (24 tests), including against `AppModel` + `InMemoryBackend` + `GTDFixtures`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureNextTests`
