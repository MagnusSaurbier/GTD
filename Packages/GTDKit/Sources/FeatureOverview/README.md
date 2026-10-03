# FeatureOverview

The Mac shell (E3): sidebar with live counts · list · note editor, plus the two lists and the
action editor no other feature target owns.

## Public API

- `OverviewView()` — the three-column shell; the guided flows (`SidebarItem.spansDetailColumn`:
  weekly review, routines) get sidebar + one wide column. `OverviewView(navigation:)` shares one
  `OverviewNavigation` with the menu bar.
- `OverviewCommands(navigation:model:)` — menu-bar shortcuts `⌘1…7`, `⌘N`, `⌘I`, `⌘Z`, and (T11)
  the fixed `⌘⇧N`/`⌘⇧S` "Move to Next"/"Move to Someday" of whatever action is open in the detail
  column, disabled when nothing is open. Both go through `AppModel.perform(_:)`, so a cap or
  `missingFields` refusal reaches the shell's one alert (STYLEGUIDE §4.5). `⌘F` lives inside the
  window, because it focuses the filter field.
- `ActionListView(status:selection:onOpen:)` — Someday, grouped by area/project. On
  macOS a selectable `List`: click or arrow keys call `onOpen`, `selection` is the highlighted row.
  Waiting, Deferred (`FeatureWaiting`) and Projects (`FeatureProjects`) take the same
  `selection:` and behave identically (M2); `OverviewView` passes `navigation.openAction` to the
  first two and `navigation.openProject` to Projects.
- `OverviewLayout` — column and window minimum sizes; `App/MacShell.swift` sizes the window from it.
- `ActionDetailView(action:onRename:)` — the autosaving note editor (also the iPhone detail).
  Autosave means: chips and pickers save at once; typed text is held until blur, close or
  `AppModel.flushHeldEdits()` — there is no typing-pause timer in the app (tests inject one).
  Below the chips sits **one** `DesignSystem.NoteEditor` over `ActionEditModel.body`: the note's
  whole body as an Obsidian-style live preview (STYLEGUIDE §4.4), `# Why?`/`# What?` being
  headings in the text. A note that lacks them shows them (`ActionEditModel.displayBody`); they
  reach the file with the first edit, never by merely opening the note.
  "Close" includes opening another row: the Mac detail column swaps editors in place with no
  `onDisappear`, so `.task(id:)` flushes the editor it replaces.
- `SidebarItem.lists` (T10) — the single `Lists` sidebar row (count = open items across every
  list, `Rules.SidebarCounts.lists`); the content column is `FeatureLists.ListsSectionsView`
  (one section per list) and the detail column is `FeatureLists.ListItemEditorView` for
  `OverviewDetail.listItem(_:)`, wired the same way `.action`/`.project` already are (`onOpen` →
  `navigation.open(listItem:)`, `OverviewNavigation.apply` follows a rename through
  `NavigationRemap`). `⌘1…n` covers every counted section in STYLEGUIDE §4.1 order.
- `SidebarItem.inProgress` (#87) — the In progress board (`FeatureNext.InProgressBoardView`) right
  under Next; a drop on it begins the action (`MoveDestination.inProgress`), and the list column
  starts wider for it (`OverviewLayout.listIdealWidth(for:)`). `ActionDetailView` shows a
  prominent **Begin action** button (`ActionEditModel.canBegin`/`begin()`, → `in-progress`) above
  the status chips, which now include Agent and Review.
- Drag-to-category (E3, 2026-09-24): `OverviewView` applies `FeatureInbox.moveNoteHost()` to
  the window, so every row of Next / Someday / Waiting / Deferred is draggable and the sidebar's
  Next · Someday · Waiting · Lists · Projects · Deferred rows (`SidebarItem.moveDestination`) and
  the project rows take the drop (Lists opens the inbox's list picker; the action becomes an item
  of the chosen list); `ActionListView`'s context menu carries the `Move to…` twin.
- `SidebarItem`, `OverviewNavigation`, `OverviewDetail`, `ActionListModel`, `ActionGroup`,
  `ActionEditModel`, `ActionField`.

Linux-compilable (and therefore tested): `SidebarItem`, `OverviewNavigation`, `ActionListModel`,
`ActionEditModel`, `OverviewCopy`, `OverviewMacCopy` / `OverviewLayout`.

## Invariants

- **The title is held while typing.** `ActionEditModel.setTitleHeld` keeps a title edit local until blur, Return or close: a title is the file name (A1), so saving on every typing pause renamed the file mid-word and popped the iPhone detail. `complete()` and `trash()` flush pending edits first, then send the existing commands; `isClosed` tells the view the action is gone.
- **Autosave never clobbers.** `ActionEditModel` keeps the remote action plus the *dirty* fields
  overlaid, and writes only dirty fields onto the *current* snapshot action. A snapshot arriving
  mid-edit updates untouched fields and leaves the edit alone. The body is **one** field
  (`ActionField.body`, 2026-09-24): while the person types in it, a remote change to any part of
  it waits until the edit is written; the chips and the title still merge field by field. The payload is built through
  `AppModel.send(deriving:)`, i.e. only when the command's turn comes — building it earlier
  raced any command still in flight and reverted that command's fields, which is what made
  `ActionEditModelTests` fail about one run in three.
- **A rename changes the `NoteID`** (`Actions/<Title>.md`, A1). After a save that included the
  title, the model re-points itself (and calls `onRename`, an optional hook nothing in the app
  needs any more). Following the rename is not the view's job: the reducer reports it in
  `Reduction.renames`, it travels with the snapshot (`GTDAppCore.SnapshotUpdate`), and the shell
  hands it to `OverviewNavigation.apply(snapshot:renames:)`, which remaps the detail column
  **before** dropping notes that are genuinely gone.
- A refused command (cap, waiting info, title collision, `missingFields`) is kept in `lastError`,
  shown inline, and **not** retried until the next edit — the user's text is never thrown away.
  `ActionDetailView`'s cap-refusal banner (moving the action open in the detail column to Next
  through the status chips) offers no "send to Someday instead" shortcut (T11, STYLEGUIDE §3.6:
  demote-or-cancel only) — it is the cap sheet for an existing action, unlike the distinct
  fallback `FeatureProjects`' step-promotion sheets keep (ARCHITECTURE §6).
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
- "Open in Obsidian" and "Copy path" (the note's absolute file path, via
  `DesignSystem.Clipboard`) are `GTDAppCore.ObsidianLink` fed by `\.vaultRootPath`
  (`DesignSystem`, set by the app shell); without a root (fixtures) neither button is shown.
- Both sheets this view presents bring their own navigation container: `InboxProcessingView`
  needs one for its toolbar, and `VaultIssuesView` needs a `Done` button or the Mac sheet cannot
  be closed at all.
- List-row commands go through `AppModel.perform(_:)`, so a refusal reaches the shell's alert
  instead of vanishing.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureOverviewTests` — 74 tests.
The SwiftUI files (`OverviewView`, `ActionListView`, `ActionDetailView`, `OverviewCommands`,
`OverviewCalendarStrip`) are
compiled only on a Mac — see the task's Result for what to check there.
