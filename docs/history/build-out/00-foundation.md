# T00 — Foundation & contracts

**Wave 0 · blocks everything · run alone, merge before Wave 1**

## Model recommendation

**Difficulty:** Hard · **Recommended model:** Opus

Keystone task: every other agent compiles against what this produces, so a subtle mistake (wrong dependency graph, a contract that doesn't survive Swift 6 strict concurrency, an `@Observable`/actor design that can't work) is multiplied by 15. Needs judgment to resolve gaps in ARCHITECTURE §4 rather than paper over them. Not a place to save tokens.

## Goal

Create the scaffold that lets ~15 agents work in parallel without touching each other's files:
the package with all targets declared, the frozen contracts from `docs/ARCHITECTURE.md` §4 as
compiling code, an in-memory backend, fixtures, minimal design components, and a buildable app shell.

## Requirements covered

Structural only. Read REQUIREMENTS §1, §2, §5 (schema), §6, all of ARCHITECTURE.md, and STYLEGUIDE §0–§3 (for `DesignSystem`).

## Owns

Everything listed in ARCHITECTURE §2 that doesn't exist yet. After this task, ownership passes to the tasks named there.

## Deliverables

1. **Tooling:** `brew install xcodegen` (document in README). `project.yml` with one multiplatform
   target `GTD` (iOS 26, macOS 26, bundle id `com.magnussaurbier.gtd`, Swift 6), depending on the
   local package. `App/GTDApp.swift` shows a placeholder root view using `AppModel` +
   `InMemoryBackend`. `.xcodeproj` stays git-ignored.
2. **`Packages/GTDKit/Package.swift`** declaring *every* target and test target from ARCHITECTURE §2
   with the dependency graph given there, platforms iOS 26 / macOS 26, `defaultLocalization: "en"`, a `Resources` folder processed for every UI target, Swift language mode 6, Yams
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
7. **`DesignSystem` minimal but working, API frozen** — names and states exactly as in
   `docs/STYLEGUIDE.md` §2–§3: token namespaces (`Spacing`, `Radius`, `Typo`, `Motion`, `Elevation`,
   colour tokens + asset catalog with the accent/signal colour sets), `Chip` with
   `ChipState { unset, suggested, confirmed, disabled }`, `FlowLayout`, thin group helpers
   `ContextChipGroup` / `TimeBucketChipGroup` / `DateValueChip` (stock graphical `DatePicker`, no
   quick-pick menu), `Badge` (+ `Signal` → badge mapping), `ActionRow`, `ProjectRow`, `ItemCard`,
   `UndoToast`, `GlassActionBar`, `WaitingInfoSheet(initial:suggestedWho:onSave:)` (who + follow-up
   date both required; +7 d shown as a *suggested* chip, not pre-filled), `Symbols` (icon map §7)
   and `Copy` (canonical strings §6.3). Empty states use stock `ContentUnavailableView` — no
   custom component. T12 refines visuals behind the same API.
   **Verify first:** asset catalog + per-target `Localizable.xcstrings` in a SwiftPM package with
   `bundle: .module` — works under `xcodebuild`, degrades harmlessly under `swift build`/`swift test`
   (ARCHITECTURE §5). If not, record the workaround as a contract change before Wave 1 starts.
8. **Codec / vault / stats / notifications API stubs:** public signatures from ARCHITECTURE §4 with
   `fatalError("T10")`-style bodies so dependants compile.
9. **`scripts/check.sh`:** `swift build` + `swift test` in the package, then
   `xcodebuild build` of the package scheme for `generic/platform=iOS Simulator`.
   Optional `--app` flag: `xcodegen && xcodebuild` the app for macOS.
10. Root `README.md` update: setup steps, how to run checks.
11. **`CLAUDE.md` "Commands" section:** replace the placeholder with the exact commands you ran
    (package build, all tests, a single test target / single test, iOS-simulator build, app build,
    Xcode project regeneration). Verified only.
12. **`scripts/check-docs.sh`** (called from `check.sh`): extracts backticked repo-relative paths
    from `CLAUDE.md` and `README.md` and fails if one doesn't exist (allow-list for paths that are
    intentionally future or git-ignored, e.g. `*.xcodeproj`); fails if the
    `<!-- PHASE: build-out -->` marker is present while `agent_task/` is gone, or vice versa.
13. A `README.md` in every target directory you create (stub for unimplemented targets: one line
    purpose + "owned by TNN"); full ones for `GTDModel`, `GTDAppCore`, `GTDFixtures`, `DesignSystem`.

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

All recorded in `docs/ARCHITECTURE.md` (§2, §4, §5, §6). Additions only — nothing was removed.

| # | Change | Where | Why |
| --- | --- | --- | --- |
| T00-1 | **`extraOps` owns any path it names**; the `GTDServices` snapshot diff emits nothing for that path. A removed entity with no matching `extraOp` means "move to `GTD/Trash/`". | §4 | Inbox filing, archiving, renaming and converting move files that the diff would otherwise also try to handle. Without this rule T16 has no deterministic way to combine the two. |
| T00-2 | `GTDBackend.currentSnapshot() async -> VaultSnapshot` added. | §4 | `AppModel.send` must leave `snapshot`/`undoLabel` correct when it returns, instead of racing `snapshots()`. Trivial for both backends and it makes every feature test deterministic. |
| T00-3 | `AppModel.lastError: (any Error)?` and `AppModel.init(backend:snapshot:today:)` added. | §4 | `undo()` is `async` and non-throwing, so a refused undo (T16) needed somewhere to go. The second initialiser seeds a snapshot synchronously for previews. |
| T00-4 | `saveWeeklyReview` sets `snapshot.lastReview` and emits **no** `extraOps`; `GTDServices` encodes the `KW` note from the diff. | §4 | T11's brief left this open. Keeps markdown generation out of `GTDModel`. |
| T00-5 | Colour tokens are **code-defined**, not asset-catalog-dependent. Strings are `String` constants in `DesignSystem.Copy`. | §5 | See "Verify first" below. |
| T00-6 | `FeatureReview` also depends on `FeatureProjects`. | §2 | Its brief uses `WhatsNextSheet` for stalled projects. No cycle. |
| T00-7 | Semantic value types added to `GTDModel/Rules`: `Signal`, `SignalKind`, `SignalStep`, `StalenessPolicy`, `Rules.SidebarCounts`, `Rules.ProjectRow`, `Rules.TimelineEntry`; `DesignSystem.BadgeContent` + `SignalPresentation` map them to badge text and symbols. | §4, §5 | ARCHITECTURE §5 requires "thresholds are semantics, not styling" but did not name the types. |
| T00-8 | `GTDConfig`, `Area`, `WeeklyReview` carry a `passthrough`; `Project` and `Routine` already did. Drafts, `NoteID`, `Day`, `DayTime` are `Codable`. | §4 | Round-trip rule (N2) applies to config, area and review notes too. `Codable` is needed for T27's resumable wizard state and T26's device settings. |
| T00-9 | `VaultLayout` grew path builders (`actionPath`, `projectPath`, `areaPath`, `archivePath`, `routineLogPath`, `reviewPath`, `trashPath`, `knowledgePath`, `inboxPath`, `sanitize`). | §4 | The reducer, T15 and T16 all need the same file-naming rules; duplicating them would guarantee divergence. |

### Verify first (deliverable 7) — asset catalog and `.xcstrings`

`xcodebuild` cannot run here, so the setup was chosen to be safe under Xcode and to degrade
harmlessly on Linux, and the residual risk is written down rather than guessed away:

- `.process("Resources")` is declared **only** where a `Resources` folder exists (DesignSystem,
  the eight Feature targets, GTDIntents). On Linux `swift build` prints one
  `warning: no rule to process file … of type 'folder.assetcatalog' / 'text.json.xcstrings'`
  per catalog and copies nothing. **It does not fail the build** — those 11 warnings are expected.
- `GTDFixtures` uses `.copy("Resources/SampleVault")` instead, because the sample vault must keep
  its folder tree byte-for-byte. `Bundle.module` resolves it on Linux (there is a test).
- **Nothing depends on a catalog for correctness.** Colours are code-defined in
  `DesignSystem/Tokens/Colors.swift` (system semantic colours plus one
  `Color.dynamic(light:dark:)` over `UIColor`/`NSColor`); `Resources/Colors.xcassets` carries the
  same values for Xcode tooling only, and `App/Assets.xcassets` repeats the accent as
  `AccentColor`. The `Localizable.xcstrings` files are valid empty catalogs; T00's user-facing
  strings are `String` constants in `DesignSystem.Copy`, which T12 converts to
  `LocalizedStringResource` without changing call sites.
- **The user must confirm on a Mac** that `scripts/check.sh` is green, i.e. that the `xcodebuild`
  step compiles the catalogs and that `Bundle.module` still finds `SampleVault` there.

## Result

**Status: done.** The scaffold is in place and `scripts/check.sh` passes; 73 tests run.

### What was built

- `Packages/GTDKit/Package.swift` — all 18 source targets and 18 test targets with the dependency
  graph of ARCHITECTURE §2, `swift-tools-version: 6.2`, iOS 26 / macOS 26, `defaultLocalization:
  "en"`, Swift language mode 6 everywhere, Yams pinned with `.exact("6.2.2")`
  (latest tag; `Package.resolved` committed).
- `GTDModel` — every type, draft, command, error, prompt, `VaultFileOp`, `ReducerEnv`,
  `Reduction` from §4; `Day`/`DayTime` on integer civil-calendar maths; `VaultLayout` with
  defaults and path builders; `GTDConfig.default`; `WeeklyReview`; `Rules` (all the queries the
  features need, implemented rather than stubbed) and the `Signal`/`StalenessPolicy` types.
- **Naïve `Reducer`** handling *every* `GTDCommand`, with the cap, the waiting rule, P3 demotion,
  the P5 prompt, title collisions, archive moves and rename moves. Gaps marked `// T11:`.
- `GTDAppCore` — `GTDBackend`, `AppModel`, `InMemoryBackend` (actor, reducer only, single-level
  undo). `SnapshotHub` fans snapshots out under an `NSLock` because `snapshots()` is synchronous.
- `GTDFixtures` — `Fixtures.sampleSnapshot` (6 inbox items incl. one deferred to review, 28
  actions with **Next at 14/15**, 2 areas, 5 projects incl. one stalled and one on hold, an
  overdue waiting item, deferred and due-soon items, Morning/Bedtime routines from the brief's
  template, 10 days of routine log, a `KW 37` review) plus `Resources/SampleVault/` — 55 real
  markdown files rendered from that snapshot — and `SampleVault.copyToTemporaryDirectory()`.
- `DesignSystem` — tokens, `Symbols` (§7), `Copy`/`DateText` (§6.3), `ChipState`,
  `SignalPresentation` (§2.2), and `Chip`, `FlowLayout`, the three chip groups, `DateValueChip`,
  `Badge`, `ActionRow`, `ProjectRow`, `ItemCard`, `UndoToast`, `GlassActionBar`,
  `WaitingInfoSheet`. Empty states use stock `ContentUnavailableView`.
- API stubs for `GTDMarkdown`, `GTDVault`, `GTDServices`, `GTDStats`, `GTDNotifications`, and a
  compiling shell (root views with the exact brief signatures + a Linux-compilable model) for all
  eight `Feature*` targets and `GTDIntents`.
- `project.yml`, `App/GTDApp.swift` (fixtures behind `InMemoryBackend`), `App/Assets.xcassets`.
- `scripts/check.sh`, `scripts/check-docs.sh` (both executable), `.gitignore`,
  a `README.md` in every target directory, and the `CLAUDE.md` / `README.md` /
  `docs/ARCHITECTURE.md` updates.

### Acceptance

`GTDAppCoreTests.fileInboxToNextThenHitTheCapThenCompleteThenUndo` drives `AppModel` +
`InMemoryBackend` through the whole scenario: file a card to Next (14 → 15), the next one throws
`GTDError.nextCapReached(cap: 15)` and leaves the vault untouched, completing a DAAD action emits
`.whatsNext` and appends a project log entry, `undo()` restores the snapshot exactly.

### Deviations

- **iOS-simulator and app builds were not run** — no Xcode in this container. `scripts/check.sh`
  prints `SKIPPED: xcodebuild not available (Linux)` and exits 0, per the orchestrator's brief.
- `GlassActionBar`/`UndoToast` use `.ultraThinMaterial` instead of `.glassEffect()`, because the
  Liquid Glass API could not be compiled or checked. T12 adopts it (ARCHITECTURE §6).
- T00 implemented `Rules` properly instead of stubbing it: the Wave 1 feature agents start in
  parallel with T11 and need real lists to render.

### Files that could not be compiled on Linux (verify on a Mac)

Everything inside `#if canImport(SwiftUI)` / `#if canImport(AppIntents)`:
`DesignSystem/Tokens/Colors.swift`, `Tokens/Typography.swift`, `Components/Chip.swift`,
`Components/Rows.swift`, `Components/Containers.swift`; the view file of each Feature target
(`FeatureInbox/InboxProcessingView.swift`, `FeatureNext/NextView.swift`,
`FeatureProjects/ProjectViews.swift`, `FeatureWaiting/WaitingViews.swift`,
`FeatureRoutines/RoutineViews.swift`, `FeatureOverview/OverviewView.swift`,
`FeatureSettings/SettingsViews.swift`, `FeatureReview/ReviewViews.swift`);
`GTDIntents/CaptureIntents.swift`; and `App/GTDApp.swift` + `project.yml`.
To verify: `brew install xcodegen && scripts/check.sh --app` on a Mac with Xcode 26.
The most likely breakages are `Color.dynamic`'s `UIColor`/`NSColor` dynamic providers, the
`FlowLayout` `Layout` conformance, and `.popover`/`.presentationDetents` placement in
`DateValueChip`.

### Gotchas for the next agents

1. **Platform guards are the rule, not a suggestion** — ARCHITECTURE §5 "Platform guards" and
   CLAUDE.md "Commands". Put the logic in a Linux-compilable file, the view in a fully guarded one.
2. `swift build` prints **11 `no rule to process file` warnings** on Linux (one per string/asset
   catalog). They are expected; do not "fix" them by deleting the `Resources` folders.
3. `GTDFixtures/Resources/SampleVault` is a **generated, committed** rendering of
   `sampleSnapshot`. A test fails when they drift; regenerate with the `exportSampleVault`
   command in `CLAUDE.md`.
4. `Reducer`/`Rules` belong to T11 from now on. Everything else in `GTDModel` is frozen.
5. `AppModel.send` refreshes the snapshot before returning — feature tests need no polling.
6. The cap blocks only commands that *increase* Next occupancy, so a hand-edited 17/15 vault is
   still repairable from the app.
7. `docs/STYLEGUIDE.md` wording lives in `DesignSystem.Copy` and `SignalPresentation`. Do not
   write user-facing strings or badge text in feature code.
