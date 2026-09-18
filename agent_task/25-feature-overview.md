# T25 — Mac overview shell & lists (`FeatureOverview`)

**Wave 1 · needs T00 · links the public root views of T20–T24, T26 (placeholders exist from T00)**

## Model recommendation

**Difficulty:** Medium–hard · **Recommended model:** Sonnet — borderline

Mostly routing and standard `NavigationSplitView` work, which Sonnet does reliably. The risky parts are `ActionDetailView`'s debounced autosave (must not clobber a snapshot update arriving mid-edit, must handle rename changing the `NoteID`) and Mac focus/keyboard command plumbing. Sonnet is fine for the shell; ask for an Opus review of the autosave/rename logic, or give that view to Opus if Sonnet's version loses edits in testing.

## Goal

The Mac three-pane overview plus the generic list/detail pieces nobody else owns
(Backlog, Maybe, action detail/editor).

## Requirements covered

E3, A1, A2, N4 (replaces TaskNotes views/modals), N5 (Mac = everything), N6.

## Owns

`Sources/FeatureOverview/`, `Tests/FeatureOverviewTests/`.

## Public API

```swift
public struct OverviewView: View { public init() }                                  // Mac root
public struct ActionDetailView: View { public init(action: NoteID) }                // also used on iPhone
public struct ActionListView: View { public init(status: ActionStatus, onOpen: @escaping (NoteID) -> Void) }  // Backlog / Maybe
public enum SidebarItem: Hashable { case inbox, next, backlog, waiting, maybe, projects, deferred, review, routines }   // settings = stock `Settings` scene (T40), not a sidebar item
```

## Deliverables

- `NavigationSplitView`: **sidebar** with live counts from `Rules.sidebarCounts` (Inbox · Next ·
  Backlog · Waiting · Maybe · Projects · Deferred) + Routines, Weekly review, Settings; vault
  issue indicator when `snapshot.issues` is non-empty (click → list of issues).
  **Middle**: routes to the owning feature's view (`NextView(.full)`, `WaitingView`, …) or
  `ActionListView`. **Right**: `ActionDetailView` / `ProjectDetailView`.
- Lists are grouped **by area / project** (E3); context and time are filters (chips), never groupings. Actions without a project come first, without a section header (ARCHITECTURE §6).
- `ActionDetailView`: title (rename), status chips (cap + waiting errors handled), context +
  time chips, defer/due chips, project picker (`ProjectPicker`), *Why?* / *What?* editors
  (`MarkdownTextEditor`), "Open in Obsidian" (`obsidian://open?path=`). Autosave debounced →
  `updateAction`. "Turn into project" button appears when ≥ 2 checkboxes (A2).
- Inbox entry in the sidebar shows the count and a **Process** button (starts `InboxProcessingView` full-window); the raw list is visible read-only — processing order is forced (I1).
- `CalendarStrip` docked at the bottom of the middle column, collapsible.
- Global Mac commands: `⌘1…7` sidebar, `⌘N` quick capture, `⌘Z` undo (`AppModel.undo`), `⌘F` filter-as-you-type over titles in the current list.
- Undo toast showing `AppModel.undoLabel`.

## Acceptance

- Unit tests for grouping/filter view models and sidebar selection routing.
- Builds for iOS too (only `OverviewView` is `#if os(macOS)`-only or degrades gracefully).
- Previews: overview with fixtures, action detail in each status.
- `scripts/check.sh` passes.

## Result

**Status: done.** `scripts/check.sh` passes; `FeatureOverviewTests` runs 39 tests in 4 suites.

### What was built

`Sources/FeatureOverview/` (10 files, 4 of them SwiftUI):

- **Linux-compilable (tested):**
  - `SidebarItem` — the nine sections, `counted`/`flows` groups, `⌘1…7` mapping both ways,
    live counts from `Rules.sidebarCounts`, plural section names.
  - `OverviewNavigation` — selection, detail target, ⌘F query, capture/process/issue flags,
    calendar-strip state; changing section clears detail + filter, `replace(_:with:)` follows a
    rename, `prune(against:)` drops a note that left the vault.
  - `ActionListModel` + `ActionGroup` — grouping by area/project (ungrouped first, no header),
    title/context/time filtering, badges. Pure `filter`/`group` statics carry the logic.
  - `ActionEditModel` + `ActionField` — the debounced autosave (see below).
  - `ObsidianLink`, `OverviewCopy`/`OverviewSymbols` (the strings/symbols `DesignSystem.Copy`
    and `Symbols` do not carry yet).
- **SwiftUI:** `OverviewView` (three-column shell, sidebar with counts + cap badge + vault-issue
  row, content router, ⌘F filter bar, collapsible `CalendarStrip` dock, inbox raw list +
  *Process inbox* toolbar button, undo toast, issue/processing sheets), `ActionListView`
  (grouped list, filter chips, context menu, empty states), `ActionDetailView` (title rename,
  status chips with cap/waiting handling, context/time/defer/due chips, `ProjectPicker`,
  Why?/What? borderless editors, *Turn into project* at two checkboxes, *Open in Obsidian*),
  `OverviewCommands` (menu bar: `⌘1…7`, `⌘N`, `⌘I`, `⌘Z`).

### The autosave/rename logic (the risky part)

`ActionEditModel` keeps the remote action with only the **dirty** fields overlaid, and a save
writes **only** the dirty fields onto the *current* snapshot action:

- a snapshot arriving mid-edit updates untouched fields and never overwrites the edit, and the
  save never reverts the remote change (`aSnapshotArrivingMidEditClobbersNeitherSide`,
  `refreshAdoptsRemoteValuesOnlyForUntouchedFields`);
- a title change moves the file, so after the save the model re-points itself at
  `layout.actionPath(title:)` and calls `onRename`, which the shell forwards to the navigation;
  editing continues against the new id (`renameFollowsTheNewNoteID`, `editingContinuesAfterARename`);
- debounce and clock are injected, so coalescing is tested without wall-clock time
  (`typingCoalescesIntoOneSave`, `typingATitleRenamesOnlyOnce`);
- a refused command (cap, waiting info, title collision) is kept in `lastError`, rendered inline,
  and **not** retried until the next edit — the user's text is never discarded.

### Deviations / decisions (the user could not be asked)

1. **No `MarkdownTextEditor`** exists in `DesignSystem`, so Why?/What? use borderless
   `TextField(axis: .vertical)` as STYLEGUIDE §3.5/§4.4 describes. Swap it in when T12 ships one.
2. **`⌘F` filters only this target's lists** (`ActionListView`) through the internal
   `\.overviewQuery` environment value. `NextView`/`WaitingView`/… ignore it until they read it —
   one line each, or T41 picks it up.
3. **`⌘N` cannot capture from here**: capture writes through `GTDVault.InboxWriter`, which
   feature targets must not import (ARCHITECTURE §2). It raises
   `OverviewNavigation.isCaptureRequested`, which T40 observes and resets.
4. **The *Process inbox* button sits in the content column's toolbar** (STYLEGUIDE §4.1), not in
   the sidebar row as this brief said; the style guide wins (ARCHITECTURE §5). The sidebar inbox
   row still shows its count, and the raw captures are listed read-only (I1).
5. **`waiting` is not a plain status chip**: tapping it opens `WaitingInfoSheet`, so who +
   follow-up are set together (W1).
6. **"Open in Obsidian"** needs an absolute path; `\.vaultRootPath` (set by T40) supplies it and
   the link falls back to the vault-relative path.
7. Sidebar/section names use the plurals of STYLEGUIDE §4.1 (`Projects`, `Routines`, `Deferred`)
   instead of T00's singular `Copy` constants.

### Contract changes

Additive only, all inside this target (nothing outside `Sources/FeatureOverview` or
`Tests/FeatureOverviewTests` was edited):

| # | Change | Why |
| --- | --- | --- |
| T25-1 | `ActionDetailView(action:onRename:)` — second parameter defaulted, so the brief's one-argument form still compiles. | The shell must follow the `NoteID` a rename creates. |
| T25-2 | `OverviewView(navigation:)` added next to `OverviewView()`. | Window and menu bar must share one selection. |
| T25-3 | New public API: `OverviewCommands`, `OverviewNavigation`, `OverviewDetail`, `ActionListModel`, `ActionGroup`, `ActionEditModel`, `ActionField`, `ObsidianLink`, `EnvironmentValues.vaultRootPath`. | Menu-bar shortcuts, testable logic, and the two values the app shell has to provide. |

### Files that could not be compiled on Linux (verify on a Mac)

`Sources/FeatureOverview/OverviewView.swift`, `ActionListView.swift`, `ActionDetailView.swift`,
`OverviewCommands.swift` (all wrapped entirely in `#if canImport(SwiftUI)`; they parse cleanly
with `swiftc -parse`, which is not a type-check). What to look at first:

- `@State private var ownedNavigation = OverviewNavigation()` in `OverviewView` relies on `View`'s
  `@MainActor` inference (a `nonisolated init` is impossible — `selection` has a `didSet`).
- `NavigationSplitView` column sizing, `List(selection:)` + `.tag` in a sectioned sidebar,
  `.listStyle(.sidebar)`.
- The `@ToolbarContentBuilder` toolbar, the hidden `⌘F` button in `.background`, `@FocusState`.
- `TextField(_:text:axis:)` + `.lineLimit(3...)` in the detail form, and `FlowLayout` around
  `DateValueChip`'s popover.
- `OverviewCommands`: `CommandGroup(replacing: .undoRedo)` / `CommandMenu` + `KeyEquivalent`.
- Run the previews: overview (light/dark/AX1), Backlog + Maybe lists, detail in three statuses.

### Open issues for later tasks

- T40: hand `OverviewView(navigation:)` and `OverviewCommands(navigation:model:)` the same
  `OverviewNavigation`, observe `isCaptureRequested`, and set `\.vaultRootPath`.
- T41: give the other feature lists the `\.overviewQuery` filter, and check that the in-window
  `⌘F` button does not collide with a Find item T40 may add to the menu bar.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
=== swift test (Packages/GTDKit)
✔ Test run with 39 tests in 4 suites passed after 0.011 seconds.   (FeatureOverviewTests)
… every other target's suite passed …
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok
=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.
=== check.sh finished
```
