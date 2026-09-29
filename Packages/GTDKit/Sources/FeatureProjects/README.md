# FeatureProjects

Areas and projects: list, detail with inline steps, promotion and the "What's next?" flow (P1–P6),
plus turning a multi-checkbox action into a project (A2).

## Public API

`ProjectsListView(selection:onOpenProject:onOpenAction:)`, `ProjectDetailView(project:onOpenAction:)`,
`WhatsNextSheet(project:)`, `ConvertToProjectSheet(action:)`, `ProjectPicker(selection:)`.

`ProjectDetailView`'s header (T11) has an **area picker**: the same chip shape as `ProjectPicker`
(unset `Area` chip with the plus symbol, or the area's title confirmed) opening a popover/sheet
list of `ProjectDetailModel.areas`. It calls `setArea(_:)` directly — never `try?` — and shows a
`titleCollision`/`notFound` refusal inline under the chip (`AreaPickerContent.message(for:)`).
Clearing the area is a distinct `Remove from area` row at the bottom of the list, offered only
once the project has an area — never a "No area" option inside the list itself (STYLEGUIDE).

`ProjectsListView` is a stock selectable `List` on macOS (M2): a click or the arrow keys select a
row and selecting opens that project in the detail column; `selection` is the project that column
shows (`OverviewNavigation.openProject`). iOS keeps tap-to-open.

`ProjectPicker` is a **chip** (current project = confirmed, none = unset `Project` with the plus
symbol) that opens the project list in a popover / medium sheet — a bare `List` collapsed to zero
height inside the action detail's `ScrollView`. `ProjectPickerContent` decides title, state and rows.

Linux-compilable models (no SwiftUI — this is where the logic worth testing lives):
- `ProjectsListModel` — status filters, the folder tree (`tree`, `lines(collapsed:)`), open steps,
  demotion count, create area/project.
- `ProjectTree` / `ProjectTreePath` (#67) — the projects overview as a folder tree built from the
  project notes' paths: area-less projects (`Projects/no_area/…`, `Projects/<Name>/`) flat on top,
  every other project under the folders it sits in (area note or not), alphabetical with
  sub-folders first; `lines(collapsed:)` is the visible rows. `ProjectsListView` keeps the folded
  folders in `@AppStorage("projects.collapsedFolders")` (device state, never the vault) and draws
  folder rows like the Knowledge sheet's tree (#24) — the whole row toggles, no animation.
- `ProjectDetailModel` — header edits, **area** (`areas`, `area`, `setArea(_:)` — R-7: picking an
  area moves the project's folder, one command, one commit, one undo; `nil` moves it into
  `Projects/no_area/`, and `titleCollision`/`notFound` are thrown for the picker to show), status +
  demotion count, step add/edit/check/reorder/delete, promote, link an existing action (`linkStep`).
- `StepLinkSuggestions` — what the New step field offers while typing (#61): open actions with no
  project or this one, not yet a step here; title prefix > word prefix > inside, case- and
  diacritic-blind, at most `limit`. `↓`/`↑` highlight a row, Return or a tap links it.
- `WhatsNextModel` — one-tap step promotion, free-text action, "project is done".
- `ConvertToProjectModel` — seeds a `ProjectDraft` from an action's checkboxes, converts, promotes
  the pre-selected first step.
- `StepReorder` — pure index maths for drag + `⌥↑↓` reorder (`move(from:to:)`,
  `moveUp`/`moveDown`, `move(fromOffsets:toOffset:)` — reimplemented by hand since
  `Array.move(fromOffsets:toOffset:)` is a SwiftUI extension, not available on Linux).
- `PromotionOutcome` (`.success` / `.capReached(cap:)` / `.missingFields([RequiredField])`) —
  every promotion path returns this instead of throwing, so a view can answer the two refusals a
  promotion can *answer*: the Next cap, and the fields Next requires (R-3). Both offer the same
  fallback, "Send to Someday instead" — which always works, because a promoted step's `What?` is
  the step line itself. `promote`/`createAction` take an optional `fields: ActionDraft` for the
  `Why?`, context and time estimate a sheet collected; without it, a one-tap promotion into Next
  answers `.missingFields` rather than writing a half-committed note (ARCHITECTURE §6, T04-1).
- `AreaPickerContent` — the area picker's chip (title/state) and its two refusals' wording,
  decided outside SwiftUI so it is Linux-tested, mirroring `ProjectPickerContent`.
- `ProjectsCopy` — this target's own small strings (`removeFromArea`, the two `setArea` refusal
  messages), same pattern as `FeatureOverview.OverviewCopy` / `FeatureWaiting.WaitingCopy`.

## Platform guards (ARCHITECTURE §5)

Views live in `ProjectViews.swift`, wrapped entirely in `#if canImport(SwiftUI)` and **unverified
on Linux** — say so when reporting until built on a Mac (`scripts/check.sh --app`). Every model
above is plain Foundation + `GTDModel`/`GTDAppCore` and is covered by `swift test`.

## Known gaps / deviations

- `updateProject` still refuses a changed **title**, so the UI never offers project rename; the
  folder name is the project's identity. Its *area* is editable (R-7) through
  `ProjectDetailModel.setArea(_:)`, wired to the project detail's area picker (T11).
- `WhatsNextSheet` and `ConvertToProjectSheet` are content-sized `VStack` sheets; their step rows
  sit in `DesignSystem.OverflowScroll`, so a project with many open steps scrolls inside the
  sheet instead of pushing the buttons off the screen. Not yet seen on screen.
- Every sheet here that makes an action — `Promote` on a step (P6, `PromoteStepSheet`), a step
  or a typed line in `What's next?` (P5), and the selected step after `Turn into project` (A2) —
  hosts `FeatureInbox.MakeActionCardView` over `MakeActionModel` (`.projectStep` /
  `.newProjectAction`) since #74 (0.39): the inbox's own card, fields, asterisks, cap sheet and
  exits, so changes to the inbox card reach them. The project chip is fixed to the project.
  There is no "Send to Someday instead" shortcut any more — the card's Someday exit is it.
- The reorder chevrons (`chevron.up`/`chevron.down`) and the convert-sheet selection dot
  (`Symbols.done`/`circle`) are the closest stock symbols; STYLEGUIDE §7's icon map has no
  "move up/down" or "selected step" concept and this target cannot edit the style guide.
- A handful of field placeholders ("Project title", "New step", "Action title", …) are literal
  strings — `Copy` has no entries for them, matching the precedent `WaitingInfoSheet` already set
  with `"Who or what"` before it became `Copy.whoPlaceholder`.

## Testing

`cd Packages/GTDKit && swift test --filter FeatureProjectsTests` — 71 tests, all Linux-only
(the picker chip's content, reorder maths, grouping/filtering, step CRUD, status-change demotion, the area change of R-7 and
its refusal, the area picker's own chip/refusal wording (`AreaPickerContentTests`, T11), and the
cap-reached → Someday-fallback path on every promotion entry point).
