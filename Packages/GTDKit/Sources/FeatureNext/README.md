# FeatureNext

The default screen: filter chips over a plain list of Next actions, plus a chase section for
overdue follow-ups (E1, E2, W2).

## Public API

- `NextView(mode:selection:onOpen:onQuickCapture:)`.
  - `selection: NoteID? = nil` — the action the host shows in its detail column; its row is
    highlighted. A host that passes nothing still gets a highlight on the Mac: the list remembers
    the row it opened last.
  - `onQuickCapture` (default `nil`): I7's "capture, then jump into processing of that one card"
    needs the app shell, since `FeatureNext` must not import `FeatureInbox`. `nil` hides the
    quick-add button/`⌘N`.
- `NextViewMode { full, onTheGo }`.
- `InProgressBoardView(selection:onOpen:)` (#87) — the In progress board: In progress · Agent ·
  Review side by side when the width allows, else one list with a section per column; context
  chips + a Project menu filter every column (screen state, not persisted). Cards are draggable
  onto another column or a sidebar section; the card menu has `Move to column` and `Move to…`.
  Moves go through the host's `moveNote` handler (`MovePlan`), so the host must apply
  `FeatureInbox.moveNoteHost()` (the Mac window and the iPhone tab do). Logic:
  `InProgressBoardModel` (Linux-compilable, `FeatureNextTests/InProgressBoardModelTests`).
- Linux-compilable: `NextListModel` (filtering, sections, cap, empty states, row commands),
  `NextFilterStore` (+ `UserDefaultsNextFilterStore`, `InMemoryNextFilterStore`).

## Behaviour

- Filter chips (context multi-select, time-available single-select via `TimeBucketChipGroup`,
  reusing its 10/30/60/90 buckets for "time I have" rather than "time this takes") persist per
  device through `NextFilterStore`, namespaced by `NextViewMode` so the Mac's full list and the
  iPhone's on-the-go list don't share filters. `.onTheGo`'s context restriction lives in
  `Rules.onTheGoNextList` itself — the context chips just narrow within it. Only the separate
  `Only mobile` chip (`NextListModel.setShowsAllContexts`, E2, on by default, switching it off lifts it, persisted per
  device, untouched by `Clear filters`) lifts it; turning it back off drops picked contexts
  that are not on the go.
- Chase section (overdue follow-ups) is unaffected by the filters; quick actions bump +7 d /
  resolved (= complete).
- Tick-off completes immediately; an undo toast (`AppModel.undoLabel`, auto-dismiss 5 s) covers
  it, independent of the backend's own single-level undo bookkeeping (`⌘Z` keeps working after
  the toast fades). Inline checkboxes for actions with ≥ 2 checkboxes; ticking every one *offers*
  to complete the action (a separate button) rather than doing it automatically.
- Row context menu (all rows) / iOS swipe (trailing `Done`, leading `Someday`): done, start
  (→ in-progress), demote to Someday, set waiting (`WaitingInfoSheet`), defer (`DateValueChip` in
  a small sheet). Every swipe action has a context-menu twin — the Mac has no swipes and
  VoiceOver cannot reach one (STYLEGUIDE §8).
- **Deferring a Next row changes only the date** (R-2, ARCHITECTURE §6): a Next item may carry a
  future `defer`. It is hidden until then and holds no cap slot while hidden
  (`Rules.countsTowardCap(_:today:)`); on its date it is back with the `back` badge. Nothing is
  demoted behind the user's back.
- **`showsCapSheet`** is the R-2 flag the view acts on: Next can be over the cap when a deferred
  item returns, and the `Next is full` sheet is then presented **once per foreground**
  (`enteredForeground()` arms it, `capSheetShown()` puts it down) until something is demoted.
  `NextView` wires this itself (T11): `@Environment(\.scenePhase)` calls `enteredForeground()` on
  every transition to `.active`, and `NextCapSheet` (built locally from `DesignSystem` pieces —
  this target does not import `FeatureInbox`) lists the current Next items with `Demote` buttons
  and `Cancel`, **no "send to Someday instead" shortcut** (STYLEGUIDE §3.6). `isCapSheetPresented`
  stays true once armed, independent of `showsCapSheet` itself flipping back to `false` the
  instant `capSheetShown()` is called.
- Every row command goes through a small `run(_:)` wrapper that turns a thrown `GTDError` — a cap
  refusal or a `missingFields` refusal (R-3, named via `Copy.missingFields`) alike — into an alert
  instead of a silent `try?` (a refused command must reach the person).
- **Chase row title** (STYLEGUIDE §3.3): `Chase: <who> — <what>` when the action has a `who`,
  `Chase: <what>` when W1/D39 leaves it empty — never a dangling "— ". Built by
  `NextListModel.chaseTitle(for:)` (pure, Linux-tested) and passed into `NextRow`'s `title`, which
  is what the row actually displays and speaks (`action.title` is only the *default* for a plain
  Next row).
- Next section header (STYLEGUIDE §2.2): `Next · 14/15` as plain text below the cap, `Next` +
  `Badge` (`15/15`, overdue past it) at/above — never a meter, never a bare number. When the list
  shows fewer rows than that count the header's trailing text says why: `8 of 14 on the go`
  (iPhone), `3 of 14 shown` (filtered). Wording lives in `NextListModel`.
- Rows are `NextRow`, not `DesignSystem.ActionRow`: the title gets the full width (3 lines) and
  the badges drop under the meta line whenever title + badges do not fit on one line
  (`ViewThatFits`); the completion circle and the opening target are siblings, never nested.
- Opening a row. Mac: a stock `List(selection:)` — click anywhere on the row or use the arrow
  keys; selecting is opening, the system selection colour is the selected state. iPhone: the
  row's text area is a plain `Button`. Both are exposed to accessibility as one button whose
  label is `NextListModel.spokenLabel(for:)`; the circle is a separate `Done <title>` button.
- Filter chips sit in the list's top safe-area bar, under the inline bar title
  (`pinnedScreenTitle`); the list is the screen's scroll view and neither moves with it. A filter
  icon at the right end of the context caption folds all chips away (#36, `@AppStorage
  "next.filtersCollapsed"`, per device); it is filled in the accent while a filter is set. iPhone: one horizontally scrolling line. Mac: two
  wrapping rows (contexts, then time + `Clear filters`) — nothing is cut off at narrow widths.

## Contract-adjacent additions (recorded here, not a §4 contract change)

Added to `DesignSystem.Copy`: `start`, `resolved`, `quickCapture`, `actionFailed`,
`bumpFollowUp(days:)`. Added to `DesignSystem.Symbols`: `checkboxOn`/`checkboxOff` (SF Symbols
`checkmark.square`/`square` — STYLEGUIDE §7 has no checklist-row entry yet; flagged there as a
gap, not filled in the guide itself since it is a synced vault note).

## Platform guards (ARCHITECTURE §5)

`NextView.swift` and `NextRow.swift` are wrapped entirely in `#if canImport(SwiftUI)` — they do
not compile on Linux; build them on a Mac (`scripts/check.sh --app`).
`NextListModel.swift` and `NextFilterStore.swift` have no SwiftUI import and are fully covered by
`swift test` (32 tests), including against `AppModel` + `InMemoryBackend` + `GTDFixtures`.

## Gotchas

- **Row and header heights are rounded up to whole points** (`WholePointHeight` in
  `NextView.swift`). Fractional heights (89.67 pt) make the iOS list leave a 1 px gap between two
  cells now and then; the grouped background shows through as a stray full-width hairline.
- **Do not give the top chip bar a material background.** With `.background(.bar)` on a
  `safeAreaInset` iOS 26+ blurs the large title away; `safeAreaBar(edge: .top)` gets the system's
  scroll-edge blur under the chips without that.
- **Read a `View`-conforming type's static member into a local `let` before an `@Sendable`
  closure**, don't reference it from inside one. `nextRowChrome()`'s `.alignmentGuide` closure
  reading `NextRow.separatorInset` directly warned ("main actor-isolated static property
  referenced from a Sendable closure"); capturing it in a local first (T11) fixed the warning
  without silencing the check.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureNextTests` — 45 tests.
