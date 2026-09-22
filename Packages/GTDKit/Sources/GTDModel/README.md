# GTDModel

Pure domain layer: the value types of the vault, every mutation as a `GTDCommand`, the reducer
that applies them, and the derived queries the UI reads. **No SwiftUI, no file system.**
Compiles and tests on Linux.

## Public API

- `Core/` — `NoteID`, `Day` + `DayTime` (integer civil calendar), `VaultLayout` (folder defaults
  and every path builder), `RenameMap` (old id → new id, `resolve`/`merging`), `CaptureText`
  (R-4: the title a capture is filed under, and the body that keeps what the title could not).
- `Entities/` — `InboxItem`, `Action`, `GTDList`, `ListItem`, `Area`, `Project`, `ProjectStep`, `LogEntry`, `Routine`,
  `RoutineStep`, `RoutineLogEntry`, `GTDConfig`, `VaultIssue`, `WeeklyReview`, `VaultSnapshot`,
  `NotePassthrough`, `Checkbox`, `ActionStatus`, `ProjectStatus`, `TimeBucket`, `RoutineStepResult`.
- `Commands/` — `ActionDraft` (incl. `newProjectTitle`, R-8, and `preamble`, R-4),
  `ProjectDraft`, `WaitingInfo` (`who` optional, W1/D39), `KnowledgeTarget`, `InboxDecision`,
  `GTDCommand`, `RequiredField` (+ `RequiredField.missing`, R-3), `GTDError`, `AppPrompt`,
  `VaultFileOp`.
- `Reducer/` — `ReducerEnv`, `Reduction` (incl. `filedNotes`: notes that live in no collection —
  today the Knowledge note an inbox filing writes), `FiledNote`,
  `Reducer.reduce(_:_:env:) throws(GTDError)`.
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
- Waiting needs a **follow-up date**; who is optional and, when empty, writes no `waitingFor:`
  line at all (W1/D39). Leaving `waiting` clears both. Closed actions always carry a closing
  date; re-opening clears it. Contexts come from `GTDConfig` (values already in a note survive
  an edit).
- **Required fields are a reducer rule (R-3).** `RequiredField.missing` answers what a tier is
  still missing, and `normalize` throws `.missingFields` on every *new* transition into one:
  Next asks for `Why?` + `What?` + a context + a time estimate, a newly created Someday or
  Waiting note for `What?`, Waiting always for its follow-up date, and Done/lists/Knowledge/Trash
  for nothing. A note already in its tier is left alone and **demoting is never refused** — the
  vault has to stay repairable.
- **The capture text is the title (R-4).** Filing renames the capture file to
  `CaptureText.title(of:)` (first line, sanitised, cut at a word boundary to ≤ 60 characters) and
  *moves* it; whatever the title could not hold becomes the note's first paragraph
  (`Action.preamble`) or the head of a Knowledge/list note's body. Only whitespace is refused.
- **The project chip is a draft field (R-8).** `ActionDraft.newProjectTitle` creates the project
  it links, area-less and in the same command; naming an existing one as well is `.invalid`.
  There is no inbox Project *target* any more.
- **A project's area is the folder its folder sits in** (P1, R-6/R-7). An area-less project lives
  in `Projects/no_area/` — a *folder*, never an `Area`: no area may be called `no_area`
  (case-insensitively), and a project inside it writes no `area:` line. Changing the area is one
  command: `updateProject` emits one `VaultFileOp.moveFolder`, re-points every action's `project:`
  link so it is rewritten in the same commit, and reports the project note plus every file inside
  the folder in `Reduction.renames`. Promoted-step links point at actions and stay put. A taken
  destination is `.titleCollision`; a changed **title** is still `.invalid`.
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
  reserved name, list names are compared case-insensitively (the file system is), and the list
  commands are `createList` / `renameList` / `removeList` / `setFavouriteLists` /
  `pruneFavouriteLists` /
  `updateListItem` / `completeListItem` / `trashListItem` / `promoteListItem`.
- **A list item is never an action**: no `Rules` query for actions, no stat, no notification and
  no review card can see one, and `promoteListItem` is the only door between the two — it goes
  through the same `makeAction` + `checkCap` as an inbox filing.
- `GTDConfig.favouriteLists` is `Optional` on purpose: `nil` means "never chosen" and
  `Rules.favouriteLists` derives the first four lists alphabetically, which is never written back.
  A stored favourite follows its list: `renameList` renames it in place, `removeList` drops it,
  and `Rules.favouriteLists` skips a name whose folder vanished outside the app until
  `pruneFavouriteLists` (launch, the inbox's Knowledge / List card) drops it from the file — a
  no-op when nothing is stale or when the vault shows no list at all.
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
- Renaming an action moves the file and rewrites `ProjectStep.promotedTo`. Renaming a **project**
  is still refused (`.invalid`) — the folder name is its identity — but re-filing one into another
  area is `updateProject`'s folder move (R-7), and it takes its *source* from the note's real path,
  so a pre-rework project still sitting directly in `Projects/` moves out of there correctly. Such
  a project is never moved on its own (R-6, `docs/MANUAL_TEST.md` §9).
- `GTD/Trash/<file>` keeps the source file name; `GTDServices` uniquifies on collision — a
  removed list lands there as a whole folder, under a free name.
- `Rules.listItems(_:in:finished:)` needs the `finished:` flag: the open items and the `Done/`
  log are two different lists of the same shape, and mixing them is the one mistake the type
  system cannot catch here.

## Ownership and testing

Everything here is domain code: no `import SwiftUI`, no I/O, no markdown. A change to a rule or
to the reducer is a change to what the app *means* — read `docs/CONTRIBUTING-AGENTS.md` first.
`swift test --filter GTDModelTests` — 223 tests. `TestVault` builds tiny snapshots for the rule tables,
`GTDFixtures.sampleSnapshot` is used where a rule needs a whole system.
