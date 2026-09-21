# T21 — Next view (`FeatureNext`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Easy–medium · **Recommended model:** Sonnet

A filtered list with chips, badges and row actions over ready-made `Rules` queries; view model is plain and unit-tested. Low risk.

## Goal

The default screen: "what can I do right now?" in one glance.

## Requirements covered

E1, E2, W2 (chase items), D1 badges, A2 (turn-into-project hint), A5, N5.

## Owns

`Sources/FeatureNext/`, `Tests/FeatureNextTests/`.

## Public API

```swift
public struct NextView: View { public init(mode: NextViewMode, onOpen: @escaping (NoteID) -> Void) }
public enum NextViewMode { case full, onTheGo }      // onTheGo = iPhone: hard-filtered to config.onTheGoContexts
```

## Deliverables

- Filter chips on top: context (multi) and time available (single); filters persist per device.
  In `.onTheGo` the context chips only offer the on-the-go set and the hard filter can't be removed.
- Plain list below via `Rules.nextList`: in-progress pinned, then Next; project shown as a label;
  badges for due-soon / overdue / returned-from-defer; "chase" items from overdue follow-ups in
  their own top section with quick actions *bump +7 d* / *resolved*.
- Cap display per STYLEGUIDE §2.2: plain count, turning into an attention badge `15/15` at cap (overdue style above cap). No meter component.
- Tick-off: completes immediately, row disappears with an undo toast (N6). Inline checkbox toggling
  for multi-checkbox actions; completing the last checkbox offers to complete the action.
- Row context menu / swipe actions: start (→ in-progress), demote to Backlog, set waiting (who + date sheet), defer (`DateValueChip`). iOS swipe actions exactly as STYLEGUIDE §3.3: trailing full-swipe `Done`, leading `Backlog`.
- Quick add (Mac `⌘N`, iPhone button) = capture to inbox and jump into processing of that one card (I7) — expose as a callback `onQuickCapture`, don't import `FeatureInbox`.
- The `whatsNext` prompt is **not** presented here — `AppModel.prompt` is handled by the shell. "Turn into project" is an inline button in the detail view (T25), not in rows.
- View model (`NextListModel`) is plain and unit-tested: filtering, sections, ordering, empty states ("nothing fits 10 min at `errands`").

## Acceptance

- Unit tests for the view model incl. on-the-go filtering and chase section.
- Previews for both modes, empty state, at-cap state.
- `scripts/check.sh` passes.

## Result

**Status: done.**

### What was built

- `NextListModel` (Linux-compilable, `Sources/FeatureNext/NextListModel.swift`): filters
  (`contexts`, `timeAvailable`) persisted per device through a new `NextFilterStore` seam
  (`NextFilterStore.swift`: `UserDefaultsNextFilterStore` default, `InMemoryNextFilterStore` for
  previews/tests), namespaced by `NextViewMode` so the Mac full list and the iPhone on-the-go
  list never share filters. Computed `items`/`chase` from `Rules.nextList` /
  `Rules.onTheGoNextList` / `Rules.chaseItems`; `capCount`/`capBadge` from
  `Rules.countsTowardCap`/`Rules.capSignal`; `emptyStateTitle`/`Body` switch on `isFiltered`;
  `showsChecklist`/`allChecked` for the inline-checklist offer (A2). Row-command methods
  (`complete`, `start`, `demoteToBacklog`, `setWaiting`, `setDefer`, `toggleCheckbox`,
  `bumpFollowUp`, `resolveChase`) wrap `AppModel.send`.
- `NextView` (SwiftUI, blind): filter bar (`ContextChipGroup` + `TimeBucketChipGroup`, reused for
  "time available" rather than "time estimate" — same component, different semantic, chips still
  write 10/30/60/90), chase section with bump/resolved (swipe + context menu), Next section with
  start/demote/waiting/defer (swipe + context menu), inline checklist, cap header, undo toast
  (view-local 5 s auto-dismiss, independent of `AppModel`'s own undo bookkeeping so `⌘Z` still
  works after it fades), `⌘N`/toolbar quick-capture button, empty states (plain vs. filtered, with
  a `Clear filters` action), 4 previews (full, on-the-go, empty, at-cap).
- `NextListModelTests.swift`: 24 tests against `AppModel` + `InMemoryBackend` + `GTDFixtures`
  covering filtering, on-the-go hard-filter semantics, persistence (incl. per-mode isolation), cap
  (below/at/above, ignoring the view's own filters), chase + its quick actions, the inline
  checklist offer (ticking every box never auto-completes), and every row command including the
  defer-demotes-first path below.

### Contract-adjacent additions

Not ARCHITECTURE §4 contracts, but shared-file edits, recorded here per the brief's process:
- `DesignSystem/Copy.swift`: `start`, `resolved`, `quickCapture`, `actionFailed`,
  `bumpFollowUp(days:)`.
- `DesignSystem/Symbols.swift`: `checkboxOn`/`checkboxOff` (`checkmark.square`/`square`) for the
  inline checklist — STYLEGUIDE §7 has no checklist-row entry; flagged in code as a gap rather
  than edited into the guide (it's a synced vault note).
- `NextView(mode:onOpen:onQuickCapture:)` adds a third, defaulted-`nil` parameter beyond the
  brief's own two-argument signature (see Deliverables: "expose as a callback `onQuickCapture`").
  Existing two-argument call sites still compile; `nil` just hides the button.

### Deviation from a T11 change (merged mid-task)

T11's hardened reducer now refuses a future `deferDate` on a `next`/`in-progress` action
(`GTDError.invalid("A deferred action cannot sit in Next")`) and never demotes it for you.
`NextListModel.setDefer` now demotes to Backlog first (its own explicit `setStatus` command) when
setting a date on a cap-counting action, then sets the date — two real, visible state changes.
Every row command also runs through `NextView`'s `run(_:)` wrapper, which turns any thrown
`GTDError` into an alert instead of the `try?` it started as, per the coordinator's note that a
refused command must reach the person, not disappear silently.

### Open issues / judgment calls

- "Resolved" on a chase item completes the action (`.complete`). The requirements don't say what
  "resolved" means precisely (the wait is over, vs. the action becomes actionable again); complete
  was the simplest, most defensible reading and is fully undoable.
- The "Defer" context-menu action opens a small sheet around `DateValueChip` rather than the
  chip's own popover, since a context-menu item can't host a popover directly (STYLEGUIDE §3.1
  already prescribes popover-on-Mac/sheet-on-iOS for this chip; the sheet wraps both).

### Files unverified on Linux (verify on a Mac, `scripts/check.sh --app`)

`Sources/FeatureNext/NextView.swift` — the entire file is guarded in `#if canImport(SwiftUI)` and
was written and reviewed without a compiler. Areas most worth a close look on a Mac: the
`ScrollView(.horizontal)` + `FlowLayout`-based filter bar (does it actually scroll vs. wrap as
intended), `.swipeActions`/`.contextMenu` stacking on the same row, the two-sheet setup
(`waitingSheetAction`/`deferSheetAction` as separate `Action?` `@State`), and the
`.alert(_:isPresented:actions:)` overload used for `errorMessage`.

### `scripts/check.sh` (tail)

```
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```
`swift build` and `swift test` (full suite, all targets) are green; `FeatureNextTests` is 24/24.
