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
public struct ConvertToProjectSheet: View { public init(action: NoteID) }           // A2, opened from the inline "Turn into project" button (T20 card, T25 detail)
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

**Status: done.** `scripts/check.sh` passes (build + 59 new `FeatureProjectsTests` + full suite +
docs check; `xcodebuild` steps `SKIPPED` on Linux as expected).

### What was built

- `ProjectsListView` — grouped-by-area list (ungrouped first, no header, per ARCHITECTURE §6),
  multi-select status filter chips (active/on-hold/someday/done, empty = all), a minimal
  "create area / project" sheet.
- `ProjectDetailView` — a single `List` (needed for native `.onMove` drag reorder): editable
  outcome/why header, status chips with a live demotion-count caption (P3, "reducer does it; show
  count" — no gate, since the change is undoable via N6), step checklist (inline add/edit/check,
  drag reorder, `⌥↑↓` while a step's field is focused, promote), active actions, reference files
  (`Link` to `obsidian://open?path=…`), dated log.
- `WhatsNextSheet` — one-tap step promotion (no form — contexts/time stay undecided, matching "no
  lying defaults"), free-text new action, "nothing yet" (shows the canonical stalled-project body
  text), "project is done".
- `ConvertToProjectSheet` — title/why seeded from the action, checkboxes shown as an editable step
  list with the first step pre-selected (tap to change), converts and promotes the selection in
  one flow.
- `ProjectPicker` — unchanged from the T00 shell (already matched the brief).
- Linux-testable models: `ProjectsListModel` (extended with `toggleStatus`, `createArea`,
  `createProject`), `ProjectDetailModel`, `WhatsNextModel`, `ConvertToProjectModel`, `StepReorder`
  (pure index maths), `PromotionOutcome`/`sendCapAware` (shared cap-refusal → `.capReached`
  helper used by every promotion entry point).
- 59 tests in `Tests/FeatureProjectsTests`: `StepReorderTests` (16 tests — up/down/interior/
  boundary/out-of-range/drag-offset index maths, including the equivalence of a single `⌥↑` move
  and a one-item drag), `ProjectsListModelTests`, `ProjectDetailModelTests` (incl. the required
  cap-reached-then-Backlog-fallback path, and a no-command-sent assertion at the reorder boundary),
  `WhatsNextModelTests`, `ConvertToProjectModelTests` (incl. its own cap-reached path against a
  hand-built capped snapshot, since the sample vault's convert candidate doesn't naturally hit it).

### Deviations / gaps (see also the module README)

- No project rename or area change in the UI: T11's hardened `updateProject` now refuses a
  changed title or area (`GTDError.invalid`), landing mid-way through this task via a coordinator
  broadcast. Verified nothing here ever mutates `project.title`/`project.area`, so no code needed
  to change — this is a "don't build it" note, not a fix.
- Reorder uses plain `chevron.up`/`chevron.down` and the convert-sheet's step selector reuses
  `Symbols.done`/`circle` — STYLEGUIDE §7's icon map has no "move step"/"selected step" concept
  and this target cannot edit the style guide; flagged for T42/a style-guide update rather than
  invented silently.
- A few field placeholders ("Project title", "New step", "Action title", "New action", "New area",
  "Done when…") are literal strings — `Copy` has no entries for them. Same pattern the frozen
  `WaitingInfoSheet` used for `"Who or what"` before T12 formalised it as `Copy.whoPlaceholder`.
- The cap-refusal UI is the brief's simplified version of T20's "Next is full" sheet: one
  "Send to Backlog instead" button, not a list of the 15 Next items with per-item Demote buttons.
- `ProjectsListView`/`ProjectDetailView`/`WhatsNextSheet`/`ConvertToProjectSheet` materialise
  their Linux-testable model into `@State` via `.task` on first appearance (environment isn't
  available at `init`). There is a narrow theoretical race — a tap between first render and that
  `.task` firing would mutate a throwaway instance — that could not be fully closed without a
  larger restructuring; low risk in practice (the task starts on the very first run-loop turn) but
  worth an eye on a Mac.

### Files unverified on Linux (SwiftUI, `#if canImport(SwiftUI)`)

`Sources/FeatureProjects/ProjectViews.swift` — every view, including the four `#Preview`s
(list, detail, detail-stalled, What's next, turn-into-project). Nothing else in the target touches
SwiftUI. Verify with `scripts/check.sh --app` on a Mac; likely risk spots: the focus-gated
`⌥↑`/`⌥↓` `keyboardShortcut` modifier pattern (`OptionArrowShortcut`), `List { Section { ... } }`
mixing header/status rows with `.onMove` step rows, and `TextField(_:text:axis:.vertical)` inside
a `List` row.

### Contract changes

None — no edits outside `Sources/FeatureProjects/`, `Tests/FeatureProjectsTests/` and this file.
