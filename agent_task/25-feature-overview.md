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

_(fill in when done)_
