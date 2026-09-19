# FeatureProjects

Areas and projects: list, detail with inline steps, promotion and the "What's next?" flow (P1–P6),
plus turning a multi-checkbox action into a project (A2).

## Public API

`ProjectsListView(selection:onOpenProject:onOpenAction:)`, `ProjectDetailView(project:onOpenAction:)`,
`WhatsNextSheet(project:)`, `ConvertToProjectSheet(action:)`, `ProjectPicker(selection:)`.

`ProjectsListView` is a stock selectable `List` on macOS (M2): a click or the arrow keys select a
row and selecting opens that project in the detail column; `selection` is the project that column
shows (`OverviewNavigation.openProject`). iOS keeps tap-to-open.

`ProjectPicker` is a **chip** (current project = confirmed, none = unset `Project` with the plus
symbol) that opens the project list in a popover / medium sheet — a bare `List` collapsed to zero
height inside the action detail's `ScrollView`. `ProjectPickerContent` decides title, state and rows.

Linux-compilable models (no SwiftUI — this is where the logic worth testing lives):
- `ProjectsListModel` — grouping by area/status filters, open steps, demotion count, create area/project.
- `ProjectDetailModel` — header edits, status + demotion count, step add/edit/check/reorder, promote.
- `WhatsNextModel` — one-tap step promotion, free-text action, "project is done".
- `ConvertToProjectModel` — seeds a `ProjectDraft` from an action's checkboxes, converts, promotes
  the pre-selected first step.
- `StepReorder` — pure index maths for drag + `⌥↑↓` reorder (`move(from:to:)`,
  `moveUp`/`moveDown`, `move(fromOffsets:toOffset:)` — reimplemented by hand since
  `Array.move(fromOffsets:toOffset:)` is a SwiftUI extension, not available on Linux).
- `PromotionOutcome` (`.success` / `.capReached(cap:)`) — every promotion path returns this
  instead of throwing on `GTDError.nextCapReached`, so a view can offer "Send to Backlog instead"
  (a simplified version of the inbox's "Next is full" sheet) without re-deriving the cap by hand.

## Platform guards (ARCHITECTURE §5)

Views live in `ProjectViews.swift`, wrapped entirely in `#if canImport(SwiftUI)` and **unverified
on Linux** — say so when reporting until built on a Mac (`scripts/check.sh --app`). Every model
above is plain Foundation + `GTDModel`/`GTDAppCore` and is covered by `swift test`.

## Known gaps / deviations

- `updateProject` refuses a changed title or area — the UI never offers project
  rename or an area change after creation; only outcome/why/status/steps are editable in place.
- The reorder chevrons (`chevron.up`/`chevron.down`) and the convert-sheet selection dot
  (`Symbols.done`/`circle`) are the closest stock symbols; STYLEGUIDE §7's icon map has no
  "move up/down" or "selected step" concept and this target cannot edit the style guide.
- A handful of field placeholders ("Project title", "New step", "Action title", …) are literal
  strings — `Copy` has no entries for them, matching the precedent `WaitingInfoSheet` already set
  with `"Who or what"` before it became `Copy.whoPlaceholder`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureProjectsTests` — 64 tests, all Linux-only
(the picker chip's content, reorder maths, grouping/filtering, step CRUD, status-change demotion, and the cap-reached →
Backlog-fallback path on every promotion entry point).
