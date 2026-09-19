# GTDModel

Pure domain layer: the value types of the vault, every mutation as a `GTDCommand`, the reducer
that applies them, and the derived queries the UI reads. **No SwiftUI, no file system.**
Compiles and tests on Linux.

## Public API

- `Core/` — `NoteID`, `Day` + `DayTime` (integer civil calendar), `VaultLayout` (folder defaults
  and every path builder).
- `Entities/` — `InboxItem`, `Action`, `Area`, `Project`, `ProjectStep`, `LogEntry`, `Routine`,
  `RoutineStep`, `RoutineLogEntry`, `GTDConfig`, `VaultIssue`, `WeeklyReview`, `VaultSnapshot`,
  `NotePassthrough`, `Checkbox`, `ActionStatus`, `ProjectStatus`, `TimeBucket`, `RoutineStepResult`.
- `Commands/` — `ActionDraft`, `ProjectDraft`, `WaitingInfo`, `InboxDecision`, `GTDCommand`,
  `GTDError`, `AppPrompt`, `VaultFileOp`.
- `Reducer/` — `ReducerEnv`, `Reduction`, `Reducer.reduce(_:_:env:) throws(GTDError)`.
- `Rules/` — `Rules` (queries incl. `isUndoable`, `openActions`, `closedDay`, `waitingSince`),
  `Signal`/`SignalKind`/`SignalStep`, `StalenessPolicy`. The list queries are linear in the
  snapshot: `projectRows`/`stalledProjects` bucket the visible actions by project once rather
  than scanning them per project (it used to be O(projects × actions)).

## Invariants

- **No lying defaults:** undecided is `nil`/empty; `timeEstimate` is never `0`.
- `NotePassthrough` is opaque — only `GTDMarkdown` reads its slots.
- The reducer is the only place with GTD semantics; its doc comment maps each rule to the code
  that enforces it. `extraOps` owns any path it names (ARCHITECTURE §4).
- Waiting needs who **and** follow-up; leaving `waiting` clears both. Closed actions always carry
  a closing date; re-opening clears it. Contexts come from `GTDConfig` (values already in a note
  survive an edit).
- Only active projects put actions into Next; leaving `active` demotes them to Backlog.
- A future defer date and a Next slot contradict each other — refused, never auto-resolved. Only
  *new* contradictions are refused, so a hand-edited vault stays repairable.
- The cap blocks only commands that *increase* Next occupancy.
- Every `Rules` list has a **total** order (`NoteID` last), so equal snapshots render identically.
- `Day` never uses `Calendar` for arithmetic; queries converting a `Date` take a `calendar`
  parameter and the reducer passes `env.calendar`.

## Gotchas

- `countsTowardCap` counts `next` + `in-progress` regardless of defer; with the rule above it
  equals `nextList(…).count` in any vault the app wrote. `nextList` is never truncated to the
  cap — an over-cap vault must stay repairable.
- `Rules.isUndoable` is the single definition of N6: both backends call it, and the labels live
  in `GTDAppCore/UndoLabel`.
- Renaming an action moves the file and rewrites `ProjectStep.promotedTo`. Renaming or re-filing
  a **project** is refused (`.invalid`) — the folder name is its identity.
- `GTD/Trash/<file>` keeps the source file name; `GTDServices` uniquifies on collision.

## Ownership and testing

Everything here is domain code: no `import SwiftUI`, no I/O, no markdown. A change to a rule or
to the reducer is a change to what the app *means* — read `docs/CONTRIBUTING-AGENTS.md` first.
`swift test --filter GTDModelTests` — `TestVault` builds tiny snapshots for the rule tables,
`GTDFixtures.sampleSnapshot` is used where a rule needs a whole system.
