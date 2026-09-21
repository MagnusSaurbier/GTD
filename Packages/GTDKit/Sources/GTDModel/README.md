# GTDModel

Pure domain layer: the value types of the vault, every mutation as a `GTDCommand`, the reducer
that applies them, and the derived queries the UI reads. **No SwiftUI, no file system.**
Compiles and tests on Linux.

## Public API

- `Core/` — `NoteID`, `Day` + `DayTime` (integer civil calendar), `VaultLayout` (folder defaults
  and every path builder), `RenameMap` (old id → new id, `resolve`/`merging`).
- `Entities/` — `InboxItem`, `Action`, `GTDList`, `ListItem`, `Area`, `Project`, `ProjectStep`, `LogEntry`, `Routine`,
  `RoutineStep`, `RoutineLogEntry`, `GTDConfig`, `VaultIssue`, `WeeklyReview`, `VaultSnapshot`,
  `NotePassthrough`, `Checkbox`, `ActionStatus`, `ProjectStatus`, `TimeBucket`, `RoutineStepResult`.
- `Commands/` — `ActionDraft`, `ProjectDraft`, `WaitingInfo`, `InboxDecision`, `GTDCommand`,
  `GTDError`, `AppPrompt`, `VaultFileOp`.
- `Reducer/` — `ReducerEnv`, `Reduction`, `Reducer.reduce(_:_:env:) throws(GTDError)`.
- `Rules/` — `Rules` (queries incl. `isUndoable`, `openActions`, `closedDay`, `waitingSince`,
  and the list queries `lists`, `listRows`, `listItems`, `openListItemCount`, `favouriteLists`),
  `Signal`/`SignalKind`/`SignalStep`, `StalenessPolicy`. The list queries are linear in the
  snapshot: `projectRows`/`stalledProjects` bucket the visible actions by project once rather
  than scanning them per project (it used to be O(projects × actions)).

## Invariants

- **No lying defaults:** undecided is `nil`/empty; `timeEstimate` is never `0`.
- `NotePassthrough` is opaque — only `GTDMarkdown` reads its slots.
- The reducer is the only place with GTD semantics; its doc comment maps each rule to the code
  that enforces it. `extraOps` owns any path it names (ARCHITECTURE §4).
- **A rename is reported, not inferred.** Renaming an action moves its file (A1), so the old
  `NoteID` leaves the snapshot exactly as a deletion would. `Reduction.renames` says which ids
  moved where, so navigation can follow the note instead of concluding it is gone.
- Waiting needs who **and** follow-up; leaving `waiting` clears both. Closed actions always carry
  a closing date; re-opening clears it. Contexts come from `GTDConfig` (values already in a note
  survive an edit).
- Only active projects put actions into Next; leaving `active` demotes them to Someday.
- **A Next item may carry a future `defer`** (R-2). It is hidden until its date and holds no cap
  slot while hidden; on its date it returns with the `back` badge, even if that puts Next over
  the cap. Nothing is demoted automatically.
- **Trash is not a status** (I4c). `trashAction` removes the note from the snapshot and names no
  path, so the diff emits `.delete`, which `GTDVault` performs as a move into `GTD/Trash/`.
  `VaultFileOp` has no hard delete and never will: its four cases are `put`, `move`,
  `moveFolder` (R-5 — a whole directory at once, for a list rename, a removed list or a project
  changing area), `createFolder` (an empty list folder; no inverse, so `createList` is not
  undoable) and `delete`, and the last one is a move into `GTD/Trash/`.
  `ActionStatus.legacyTrashed` exists only to *read* a pre-rework `status: trash` line: it is
  closed, hidden, out of `allCases`, and the reducer refuses any move into it.
- **A list is a folder** (§5a): `Lists/<name>/` is the list, an item is a note with a title, an
  optional `created` and free notes, and `Lists/<name>/Done/` is the finished log. `Done` is a
  reserved name, list names are compared case-insensitively (the file system is), and the six list
  commands are `createList` / `renameList` / `removeList` / `setFavouriteLists` /
  `updateListItem` / `completeListItem` / `trashListItem` / `promoteListItem`.
- **A list item is never an action**: no `Rules` query for actions, no stat, no notification and
  no review card can see one, and `promoteListItem` is the only door between the two — it goes
  through the same `makeAction` + `checkCap` as an inbox filing.
- `GTDConfig.favouriteLists` is `Optional` on purpose: `nil` means "never chosen" and
  `Rules.favouriteLists` derives the first four lists alphabetically, which is never written back.
- The cap blocks only commands that *increase* Next occupancy.
- Every `Rules` list has a **total** order (`NoteID` last), so equal snapshots render identically.
- `Day` never uses `Calendar` for arithmetic; queries converting a `Date` take a `calendar`
  parameter and the reducer passes `env.calendar`.

## Gotchas

- `countsTowardCap(_:today:)` counts the `next` + `in-progress` actions that are **visible
  today**: a hidden (future-deferred) one is not a commitment for today (R-2). It therefore needs
  a `Day`, as do `isAtCap` and `capSignal`. `nextList` is never truncated to the cap — an
  over-cap vault must stay repairable.
- `Rules.isUndoable` is the single definition of N6: both backends call it, and the labels live
  in `GTDAppCore/UndoLabel`.
- Renaming an action moves the file and rewrites `ProjectStep.promotedTo`. Renaming or re-filing
  a **project** is refused (`.invalid`) — the folder name is its identity.
- `GTD/Trash/<file>` keeps the source file name; `GTDServices` uniquifies on collision — a
  removed list lands there as a whole folder, under a free name.
- `Rules.listItems(_:in:finished:)` needs the `finished:` flag: the open items and the `Done/`
  log are two different lists of the same shape, and mixing them is the one mistake the type
  system cannot catch here.

## Ownership and testing

Everything here is domain code: no `import SwiftUI`, no I/O, no markdown. A change to a rule or
to the reducer is a change to what the app *means* — read `docs/CONTRIBUTING-AGENTS.md` first.
`swift test --filter GTDModelTests` — `TestVault` builds tiny snapshots for the rule tables,
`GTDFixtures.sampleSnapshot` is used where a rule needs a whole system.
