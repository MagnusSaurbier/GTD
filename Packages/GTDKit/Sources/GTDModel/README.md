# GTDModel

Pure domain layer: the value types of the vault, every mutation as a `GTDCommand`, the reducer
that applies them, and the derived queries the UI reads. **No Foundation-beyond-basics, no
SwiftUI, no file system.** Compiles and tests on Linux.

## Public API

- `Core/` — `NoteID` (vault-relative path, `title`/`folder`), `Day` + `DayTime` (integer civil
  calendar, `iso`, `adding(days:)`, `isoWeek`, `Day.today()`), `VaultLayout` (folder defaults and
  every path builder: `actionPath`, `projectPath`, `archivePath`, `routineLogPath`, `reviewPath`, …).
- `Entities/` — `InboxItem`, `Action`, `Area`, `Project`, `ProjectStep`, `LogEntry`, `Routine`,
  `RoutineStep`, `RoutineLogEntry`, `GTDConfig`, `VaultIssue`, `WeeklyReview`, `VaultSnapshot`,
  `NotePassthrough`, `Checkbox`, and the enums `ActionStatus`, `ProjectStatus`, `TimeBucket`,
  `RoutineStepResult`.
- `Commands/` — `ActionDraft`, `ProjectDraft`, `WaitingInfo`, `InboxDecision`, `GTDCommand`,
  `GTDError`, `AppPrompt`, `VaultFileOp`.
- `Reducer/` — `ReducerEnv`, `Reduction`, `Reducer.reduce(_:_:env:) throws(GTDError)`.
- `Rules/` — `Rules` (queries), `Signal`/`SignalKind`/`SignalStep`, `StalenessPolicy`.

## Invariants

- **No lying defaults:** an undecided field is `nil`/empty. `timeEstimate` is never `0`.
- `NotePassthrough` is opaque: only `GTDMarkdown` writes or reads its slots.
- The reducer is the only place with GTD semantics. `extraOps` owns any path it names — the
  `GTDServices` diff must not touch that path (ARCHITECTURE §4).
- Waiting needs who **and** follow-up date; leaving `waiting` clears both.
- Only active projects put actions into Next; the cap only blocks commands that *increase* Next.
- `Day` never uses `Calendar` for arithmetic, so there are no time-zone or locale surprises.

## Ownership

T00 wrote the types and a **naïve** reducer + rules so the UI targets had something usable.
**T11 owns `Reducer/` and `Rules/`** and hardens them; everything else here is frozen (contract
change procedure in `agent_task/README.md`). Known gaps carry a `// T11:` comment.

## Testing

`cd Packages/GTDKit && swift test --filter GTDModelTests`.
`GTDModelTests` covers `Day`, the rules against `GTDFixtures.sampleSnapshot`, and one smoke test
per `GTDCommand`.
