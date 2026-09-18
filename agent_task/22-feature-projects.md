# T22 — Areas & projects (`FeatureProjects`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet

Several views and two sheets, but standard SwiftUI list/detail/reorder work on the in-memory backend with semantics delegated to the reducer. Check in review: step reorder index maths and the cap-error path on promotion.

## Goal

Projects list, the Mac project view, and the "What's next?" prompt.

## Requirements covered

All of §6 (P1–P7), E4, A2 (convert action to project).

## Owns

`Sources/FeatureProjects/`, `Tests/FeatureProjectsTests/`.

## Public API

```swift
public struct ProjectsListView: View { public init(onOpenProject: @escaping (NoteID) -> Void, onOpenAction: @escaping (NoteID) -> Void) }
public struct ProjectDetailView: View { public init(project: NoteID, onOpenAction: @escaping (NoteID) -> Void) }
public struct WhatsNextSheet: View { public init(project: NoteID) }                 // P5, presented by the shell
public struct ConvertToProjectSheet: View { public init(action: NoteID) }           // A2, presented by the shell
public struct ProjectPicker: View { public init(selection: Binding<NoteID?>) }      // reusable chip/sheet picker
```

## Deliverables

- **List (E4):** grouped by area; row = title, status, active action(s), remaining step count,
  stalled badge. Sections/filters for active · on-hold · someday · done. Create area / project.
- **Detail (P6, Mac-first, usable on iPhone):** header with outcome ("done when…") + why (inline
  editable); status picker (chips); step checklist with inline add / edit / reorder (drag +
  `⌥↑↓`) / check / **promote** (→ small action-draft form with contexts + time chips, status
  Next or Backlog; cap error handled like in T20 but simplified: offer Backlog);
  active actions of the project; reference files of the folder (open with system / reveal in
  Obsidian via `obsidian://open?path=`); dated log of completed actions.
- **WhatsNextSheet:** "What's next for <project>?" — remaining steps for one-tap promotion, free-text new action, "nothing yet" (project becomes stalled → say so), "project is done" (→ status done).
- **ConvertToProjectSheet:** action's checkboxes become steps, title/why carried over, first step pre-selected for promotion.
- Setting a project to non-active informs that its Next actions will be demoted to Backlog (reducer does it; show count).

## Acceptance

- Unit tests for the row/detail view models (stalled detection display, remaining count, grouping, reorder index maths).
- Previews: list, detail (normal, stalled, empty), both sheets.
- `scripts/check.sh` passes.

## Result

_(fill in when done)_
