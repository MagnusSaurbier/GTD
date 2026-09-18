# T00 — Foundation & contracts

**Wave 0 · blocks everything · run alone, merge before Wave 1**

## Goal

Create the scaffold that lets ~15 agents work in parallel without touching each other's files:
the package with all targets declared, the frozen contracts from `docs/ARCHITECTURE.md` §4 as
compiling code, an in-memory backend, fixtures, minimal design components, and a buildable app shell.

## Requirements covered

Structural only. Read REQUIREMENTS §1, §2, §5 (schema), §6 and all of ARCHITECTURE.md.

## Owns

Everything listed in ARCHITECTURE §2 that doesn't exist yet. After this task, ownership passes to the tasks named there.

## Deliverables

1. **Tooling:** `brew install xcodegen` (document in README). `project.yml` with one multiplatform
   target `GTD` (iOS 18, macOS 15, bundle id `com.magnussaurbier.gtd`, Swift 6), depending on the
   local package. `App/GTDApp.swift` shows a placeholder root view using `AppModel` +
   `InMemoryBackend`. `.xcodeproj` stays git-ignored.
2. **`Packages/GTDKit/Package.swift`** declaring *every* target and test target from ARCHITECTURE §2
   with the dependency graph given there, platforms iOS 18 / macOS 15, Swift language mode 6, Yams
   pinned. Each not-yet-implemented target gets one placeholder source file and one placeholder test
   so the package builds.
3. **`GTDModel`:** all types, drafts, commands, errors, prompts, `VaultFileOp`, `ReducerEnv`,
   `Reduction` exactly as specified. `Day` (with `Day.today`, `adding(days:)`, ISO string
   conversion), `DayTime`, `VaultLayout` with defaults, `GTDConfig.default`, `WeeklyReview`
   (week number, year, the 8 answers, next-week goal, system-fix notes).
   `Action.checkboxes` parsing may be a simple line scan here.
4. **Naïve `Reducer`:** handles every `GTDCommand` so UIs are usable: moves things between
   collections, sets statuses/dates, enforces the Next cap and `waitingInfoRequired`, emits
   `.whatsNext` on completing a project action. T11 will harden and fully test it — keep it
   straightforward, mark gaps with `// T11:`.
5. **`GTDAppCore`:** `GTDBackend`, `AppModel`, `InMemoryBackend` (reducer + single-level undo by
   keeping the previous snapshot).
6. **`GTDFixtures`:** `sampleSnapshot` (≈6 inbox items incl. one deferred-to-review, ≈25 actions
   across all statuses with Next exactly at cap −1, 2 areas, 5 projects incl. one stalled and one
   on-hold, overdue waiting item, deferred + due-soon items, Morning/Bedtime routines taken from
   the template below, 10 days of routine log). Also `Fixtures/SampleVault/` on disk with the same
   content as real markdown files (resource bundle) plus a helper
   `SampleVault.copyToTemporaryDirectory()`.
7. **`GTDDesign` minimal but working, API frozen:** `ChipPicker` (single/multi select, empty
   state), `TimeBucketChips`, `ContextChips`, `ActionRow`, `Badge` (due, deferred-returned,
   stalled, chase), `CardContainer`, `WaitingInfoSheet(initial:onSave:)` (who + follow-up date, both required, default +7 d). T12 refines visuals behind the same API.
8. **Codec / vault / stats / notifications API stubs:** public signatures from ARCHITECTURE §4 with
   `fatalError("T10")`-style bodies so dependants compile.
9. **`scripts/check.sh`:** `swift build` + `swift test` in the package, then
   `xcodebuild build` of the package scheme for `generic/platform=iOS Simulator`.
   Optional `--app` flag: `xcodegen && xcodebuild` the app for macOS.
10. Root `README.md` update: setup steps, how to run checks.

Routine template source (convert to two files under `SampleVault/GTD/Routines/`):
Morning — wake up · Record dreams · Drink TPS/Water (creatine if morning sport) · 5 min workout ·
Cold shower · Frühstück (Brainsmoothie, maybe Brötchen) · Sonnencreme · Get things done.
Bedtime — Work done by 22:00 · Brush teeth · Reflect on day (main plot, look at dayplan,
3 achievements, 3 gratitude, 1 will-do-better) · Read 30 min · Sleep by 23:30.

## Acceptance

- `scripts/check.sh` and `scripts/check.sh --app` pass on a clean clone.
- A test drives `AppModel` + `InMemoryBackend` through: file inbox item → Next, hit the cap
  (`GTDError.nextCapReached`), complete a project action (prompt emitted), undo.
- Every Feature target compiles with an empty public root view and a `#Preview` using the fixtures.
- No target violates the dependency direction in ARCHITECTURE §2.

## Contract changes

_(record any deviation from ARCHITECTURE §4 here, and update that file — you are the only task allowed to)_

## Result

_(fill in when done)_
