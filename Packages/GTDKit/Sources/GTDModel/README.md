# GTDModel

Pure domain layer: the value types of the vault, every mutation as a `GTDCommand`, the reducer
that applies them, and the derived queries the UI reads. **No SwiftUI, no file system.**
Compiles and tests on Linux.

## Public API

- `Core/` — `NoteID`, `Day` + `DayTime` (integer civil calendar), `Weekday` (a routine's `day:`), `VaultLayout` (folder defaults
  and every path builder), `RenameMap` (old id → new id, `resolve`/`merging`), `CaptureText`
  (R-4: the title a capture is filed under, and the body that keeps what the title could not).
- `Entities/` — `InboxItem`, `Action`, `GTDList`, `ListItem`, `Area`, `Project`, `ProjectStep`, `LogEntry`, `Routine`,
  `RoutineStep`, `RoutineLogEntry`, `GTDConfig`, `VaultIssue`, `WeeklyReview`, `VaultSnapshot`,
  `NotePassthrough`, `Checkbox`, `NoteBody` (the `# Heading` sections of `Action.body`),
  `ActionStatus`, `ProjectStatus`, `TimeBucket`, `RoutineStepResult`.
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
- **An action's body is one field** (2026-09-24). `Action.body` is the whole text below the
  frontmatter; `preamble`, `why` and `what` are computed over it through `NoteBody` — the one
  place in this target that knows heading syntax (a `# Title` line starts a section, fences
  don't, titles compare case- and punctuation-insensitively, `Why?` then `What?` is the
  canonical order). A body without either action heading reads as one long `What?`, and setting
  `what` on it replaces the body. `Action(why:what:preamble:)` composes the template shape, so
  the empty body is exactly `# Why?\n\n# What?`; pass `body:` to hand over a text as is.
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
  Waiting note for `What?`, a note entering Waiting for its follow-up date, and
  Done/lists/Knowledge/Trash for nothing. A note already in its tier is left alone — a waiting
  note without a follow-up date (every M2 import) stays editable and keeps the who and date it
  has — and **demoting is never refused**: the vault has to stay repairable.
- **An inbox note's title is its file name (C3/R-4, 2026-09-22).** `InboxItem.title` is
  `id.title`; `body` is everything below the frontmatter and may be empty. A capture is named
  `CaptureText.title(of:)` when it is written (first line, sanitised, cut at a word boundary to
  ≤ 60 characters); its body holds the full text only when the name could not
  (`CaptureText.note(for:)`). `renameInboxItem` moves the file within `Inbox/`
  (`.titleCollision` when taken, `.invalid` when empty); `editInboxBody` edits the body only.
  Filing keeps the file name as the note's title and *moves* the file; the body comes along as
  `Action.preamble` or the head of a Knowledge/list note's body — unless it is only the empty
  Why/What template skeleton, which counts as empty (`CaptureText.isEmptyBody`, the one place
  that knows the skeleton).
- **A card closed half-way stays an inbox note (#85).** `saveInboxProgress` keeps the card's
  body and chips in the note (`InboxProgress`; `InboxItem.contexts`/`timeEstimate`/`project`/
  `deferDate`/`due`, under the action keys). `InboxBody` is the card's view of the body: the
  capture text (`lead`) and `# Why?`/`# What?` sections, the empty skeleton excepted;
  `written(over:)` rewrites only the pieces that changed. An action filing takes those sections
  over (an empty draft field falls back to the stored one) instead of putting them under the
  preamble, and keeps any other section of the note.
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
- **Deferring is waiting — except Someday** (#86, `Rules/DeferIsWaiting.swift`). A Someday item
  with a `defer` date keeps it: hidden from every list until then, back in Someday with the `back`
  badge; leaving Someday with the date untouched drops it. Any other deferral is a waiting item with
  a follow-up date and **no who**: it is listed in Waiting and holds no cap slot until that date;
  then it is back in Next by itself (`Rules.isBackInNext`) with the `back` badge, even if that
  puts Next over the cap (R-2) — its file keeps `status: waiting` until the user changes it. A
  waiting item with a who never comes back by itself; it becomes a `chase`. `normalize` folds
  any `deferDate` a command sets on a non-Someday action into that shape (`Action.foldingDeferIntoWaiting`; picking a
  tier with `setStatus` drops it instead), and the reducer judges a deferral that is back as a
  Next item (`Rules.effectiveStatus`). Nothing is demoted automatically.
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
  `pruneFavouriteLists` / `addListItem` (a new open note stamped now — the `+` inside a list) /
  `updateListItem` / `completeListItem` / `trashListItem` / `promoteListItem` /
  `moveActionToList`.
- **A list item is never an action**: no `Rules` query for actions, no stat, no notification and
  no review card can see one, and the only two doors between them are `promoteListItem` (item →
  action, through the same `makeAction` + `checkCap` as an inbox filing) and `moveActionToList`
  (action → item, E3's drop onto a list: the file moves, the body becomes the notes).
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

- `countsTowardCap(_:today:)` counts the `next` + `in-progress` actions plus the deferrals that
  are back **today** (#86, R-2); `agent` and `review`, the In progress board's other columns, never
  count (#87). It therefore needs a `Day`, as do `isAtCap` and `capSignal`. `nextList` is never truncated to the cap — an
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
