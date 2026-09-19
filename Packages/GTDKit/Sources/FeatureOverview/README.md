# FeatureOverview

The Mac shell (E3): sidebar with live counts · list · note editor, plus the two lists and the
action editor no other feature target owns.

## Public API

- `OverviewView()` — the three-column shell. `OverviewView(navigation:)` shares one
  `OverviewNavigation` with the menu bar.
- `OverviewCommands(navigation:model:)` — menu-bar shortcuts `⌘1…7`, `⌘N`, `⌘I`, `⌘Z`
  (STYLEGUIDE §4.5). `⌘F` lives inside the window, because it focuses the filter field.
- `ActionListView(status:onOpen:)` — Backlog / Maybe, grouped by area/project.
- `ActionDetailView(action:onRename:)` — the autosaving note editor (also the iPhone detail).
- `SidebarItem`, `OverviewNavigation`, `OverviewDetail`, `ActionListModel`, `ActionGroup`,
  `ActionEditModel`, `ActionField`, `ObsidianLink`, `EnvironmentValues.vaultRootPath`.

Linux-compilable (and therefore tested): `SidebarItem`, `OverviewNavigation`, `ActionListModel`,
`ActionEditModel`, `ObsidianLink`, `OverviewCopy`.

## Invariants

- **Autosave never clobbers.** `ActionEditModel` keeps the remote action plus the *dirty* fields
  overlaid, and writes only dirty fields onto the *current* snapshot action. A snapshot arriving
  mid-edit updates untouched fields and leaves the edit alone. The payload is built through
  `AppModel.send(deriving:)`, i.e. only when the command's turn comes (T40-2) — building it
  earlier raced any command still in flight and reverted that command's fields, which is what
  made `ActionEditModelTests` fail about one run in three until T40.
- **A rename changes the `NoteID`** (`Actions/<Title>.md`, A1). After a save that included the
  title, the model re-points itself and calls `onRename`, which the shell forwards to
  `OverviewNavigation.replace(_:with:)`.
- A refused command (cap, waiting info, title collision) is kept in `lastError`, shown inline,
  and **not** retried until the next edit — the user's text is never thrown away.
- Lists group **by area / project**; context and time are filter chips. Actions without a project
  come first, without a header.
- The shell holds no GTD semantics: every section routes to the feature that owns it.

## Gotchas

- `⌘F` filters only lists this target renders (`ActionListView`, via `\.overviewQuery`). The
  other features' lists ignore it until they read that environment value.
- `OverviewNavigation.isCaptureRequested` is a request to the app shell: capture writes through
  `GTDVault`, which feature targets must not import.
- `ObsidianLink` needs `\.vaultRootPath` (set by the app shell) for an absolute path.
- Both sheets this view presents bring their own navigation container: `InboxProcessingView`
  needs one for its toolbar, and `VaultIssuesView` needs a `Done` button or the Mac sheet cannot
  be closed at all (T41).
- List-row commands go through `AppModel.perform(_:)`, so a refusal reaches the shell's alert
  instead of vanishing.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureOverviewTests`
The SwiftUI files (`OverviewView`, `ActionListView`, `ActionDetailView`, `OverviewCommands`) are
compiled only on a Mac — see the task's Result for what to check there.
