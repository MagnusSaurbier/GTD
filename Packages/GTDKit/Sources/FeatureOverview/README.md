# FeatureOverview

The Mac shell (E3): sidebar with live counts · list · note editor, plus the two lists and the
action editor no other feature target owns.

## Public API

- `OverviewView()` — the three-column shell; the guided flows (`SidebarItem.spansDetailColumn`:
  weekly review, routines) get sidebar + one wide column. `OverviewView(navigation:)` shares one
  `OverviewNavigation` with the menu bar.
- `OverviewCommands(navigation:model:)` — menu-bar shortcuts `⌘1…7`, `⌘N`, `⌘I`, `⌘Z`
  (STYLEGUIDE §4.5). `⌘F` lives inside the window, because it focuses the filter field.
- `ActionListView(status:selection:onOpen:)` — Someday, grouped by area/project. On
  macOS a selectable `List`: click or arrow keys call `onOpen`, `selection` is the highlighted row.
  Waiting, Deferred (`FeatureWaiting`) and Projects (`FeatureProjects`) take the same
  `selection:` and behave identically (M2); `OverviewView` passes `navigation.openAction` to the
  first two and `navigation.openProject` to Projects.
- `OverviewLayout` — column and window minimum sizes; `App/MacShell.swift` sizes the window from it.
- `ActionDetailView(action:onRename:)` — the autosaving note editor (also the iPhone detail).
- `SidebarItem`, `OverviewNavigation`, `OverviewDetail`, `ActionListModel`, `ActionGroup`,
  `ActionEditModel`, `ActionField`, `ObsidianLink`, `EnvironmentValues.vaultRootPath`.

Linux-compilable (and therefore tested): `SidebarItem`, `OverviewNavigation`, `ActionListModel`,
`ActionEditModel`, `ObsidianLink`, `OverviewCopy`, `OverviewMacCopy` / `OverviewLayout`.

## Invariants

- **The title is held while typing.** `ActionEditModel.setTitleHeld` keeps a title edit local until blur, Return or close: a title is the file name (A1), so saving on every typing pause renamed the file mid-word and popped the iPhone detail. `complete()` and `trash()` flush pending edits first, then send the existing commands; `isClosed` tells the view the action is gone.
- **Autosave never clobbers.** `ActionEditModel` keeps the remote action plus the *dirty* fields
  overlaid, and writes only dirty fields onto the *current* snapshot action. A snapshot arriving
  mid-edit updates untouched fields and leaves the edit alone. The payload is built through
  `AppModel.send(deriving:)`, i.e. only when the command's turn comes — building it earlier
  raced any command still in flight and reverted that command's fields, which is what made
  `ActionEditModelTests` fail about one run in three.
- **A rename changes the `NoteID`** (`Actions/<Title>.md`, A1). After a save that included the
  title, the model re-points itself (and calls `onRename`, an optional hook nothing in the app
  needs any more). Following the rename is not the view's job: the reducer reports it in
  `Reduction.renames`, it travels with the snapshot (`GTDAppCore.SnapshotUpdate`), and the shell
  hands it to `OverviewNavigation.apply(snapshot:renames:)`, which remaps the detail column
  **before** dropping notes that are genuinely gone.
- A refused command (cap, waiting info, title collision) is kept in `lastError`, shown inline,
  and **not** retried until the next edit — the user's text is never thrown away.
- Lists group **by area / project**; context and time are filter chips. Actions without a project
  come first, without a header.
- The shell holds no GTD semantics: every section routes to the feature that owns it.
- The calendar strip is docked only under Next, Waiting and Deferred
  (`SidebarItem.showsCalendarStrip`). The docked strip is `OverviewCalendarStrip` — the data and
  signal thresholds of `FeatureWaiting.WaitingListModel`, laid out for a narrow column
  (content-sized, horizontally scrolling, 24 pt markers).
- Inbox rows are not selectable: processing order is forced (I1). The way in is the labelled
  *Process inbox (n)* button at the top of that list, or `⌘I`.

## Gotchas

- `⌘F` filters only lists this target renders (`ActionListView`, via `\.overviewQuery`). The
  other features' lists ignore it until they read that environment value.
- `OverviewNavigation.isCaptureRequested` is a request to the app shell: capture writes through
  `GTDVault`, which feature targets must not import.
- `ObsidianLink` needs `\.vaultRootPath` (set by the app shell) for an absolute path.
- Both sheets this view presents bring their own navigation container: `InboxProcessingView`
  needs one for its toolbar, and `VaultIssuesView` needs a `Done` button or the Mac sheet cannot
  be closed at all.
- List-row commands go through `AppModel.perform(_:)`, so a refusal reaches the shell's alert
  instead of vanishing.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureOverviewTests`
The SwiftUI files (`OverviewView`, `ActionListView`, `ActionDetailView`, `OverviewCommands`,
`OverviewCalendarStrip`) are
compiled only on a Mac — see the task's Result for what to check there.
