# ORCHESTRATOR-NOTES — cross-task findings for T40/T41/T42

> **Archived by T42.** Everything still open when the build-out ended was folded into
> `docs/KNOWN_ISSUES.md`, `docs/ARCHITECTURE.md` §6 and the module READMEs, and the six unstarted
> briefs moved to `docs/follow-ups/`. This file is kept only as the record of what T40 and T41
> closed and why. Read `docs/KNOWN_ISSUES.md` instead; `agent_task/…` paths below now mean
> `docs/history/build-out/…`, except briefs 50–55, which are in `docs/follow-ups/`.

Collected from the Wave 1/2 reports for T40 (app integration) and T41 (QA). **T41 has been
through the whole list**: items it closed are struck out with the commit that did it; everything
still open is below, with what is actually left to do.

## Closed by T40

- ~~`FeatureOverviewTests.ActionEditModelTests` is flaky (~3/8 runs)~~ — fixed in T40
  (contract change T40-2: `AppModel` serialises commands and gained `send(deriving:)`; the
  autosave was racing another in-flight command, not `refresh()`).
- ~~Seven feature targets `import GTDFixtures` in preview code but `featureDeps` does not list
  it~~ — `Package.swift`'s `featureDeps` now includes `GTDFixtures`.
- ~~T13: T40 must re-run plan+sync on every snapshot change~~ — `NotificationService` re-plans on
  every snapshot change (2 s debounce), on foreground and in the background task.
- ~~T30: call `PendingRoute().consume()` on launch/foreground; add a `gtd://inbox` route~~ — done
  in `AppRouter`/`RootView`.
- ~~T24: host `RoutinesHomeView` directly~~ — the iPhone Routines tab does.
- ~~T25: share one `OverviewNavigation` between `OverviewView` and `OverviewCommands`; observe
  `isCaptureRequested` (⌘N); set `\.vaultRootPath`~~ — done in `MacShell`/`RootView`.
- ~~T15/T16: `rollbackFailed` must be shown to the user, never retried~~ — `RootView`'s single
  alert is fed by `AppModel.lastError` *and* shell failures.

## Closed by T41

- ~~T11/T16: `InMemoryBackend` has a private copy of the undoable rule and of the label table~~ —
  `dd7778f`: `UndoLabel` moved to `GTDAppCore`, both backends call `Rules.isUndoable`.
- ~~T16: archiving leaves `ProjectStep.promotedTo` pointing at the old `Actions/` path~~ —
  `dd7778f`: `Reducer.archiveCompleted` retargets it.
- ~~T30 gotcha #1: `CaptureError.bookmarkStale` is unreachable~~ — `dd7778f`: `InboxWriter` and
  `AppComposition` resolve the bookmark before starting scoped access, so "never picked",
  "saved but unresolvable" and "access refused" are three different errors.
- ~~T27: `StalledSweep.addNextAction` marks the project handled without a command~~ — `dd7778f`:
  `ReviewSession.markStalledHandled` verifies the project is no longer stalled instead of
  trusting the sheet.
- ~~T27: `systemFixNotes` round-trip through `encode(WeeklyReview)` must be verified once T16
  lands~~ — covered by `GTDServicesTests/EndToEndJourneyTests` (the `KW` note is decoded back
  off disk, then re-scanned cold).
- ~~T11: a future defer date on next/in-progress is refused (`.invalid`) — verify T21/T23 surface
  `AppModel.lastError`~~ — T21 did; **T23 did not** and has been fixed (`b1ec1bc`): `FeatureWaiting`
  swallowed every `GTDError` with `try?` at 10 call sites. `AppModel` gained `perform(_:)` /
  `report(_:)` (contract change **T41-1**) so a refusal reaches the shell's alert.
- ~~T20/T12: the inbox reimplements the inbox-zero reward moment~~ — `95c7793`: `InboxZeroView`
  composes `DesignSystem.RewardMoment.inboxZero`.

## Also closed by T41 (its second run)

- ~~`docs/TRACEABILITY.md` was not written~~ — written, in full: every requirement ID of
  REQUIREMENTS v1 plus §12, each with the module, the tests and a status. Six requirements come
  out **partial**; each has a brief (`50`–`55`, below).
- ~~Deliverable 3's "rename while open in detail view"~~ — two tests in
  `GTDServicesTests/SyncScenarioTests`, on real files.
- ~~Deliverable 5 (performance)~~ — `GTDServicesTests/PerformanceTests` + `scripts/benchmark.sh`,
  and the three pathologies they found are fixed (see the brief's Result for the numbers).
- ~~Deliverable 6 (accessibility)~~ — the clear omissions fixed in code, the rest in
  `docs/MANUAL_TEST.md` §6.
- ~~Deliverable 7 (first-real-use checklist)~~ — `docs/MANUAL_TEST.md` §9.

## New briefs T41 opened (not part of the original board)

Ordered by what unblocks them, not by number. `docs/TRACEABILITY.md` links each one to the
requirement it closes.

| Brief | Closes | Blocked on |
| --- | --- | --- |
| `50-mac-keyboard-map.md` | E3 — `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are not in the menu bar | Gate 2 |
| `51-search-across-lists.md` | E1/E3 — `⌘F` reaches only `FeatureOverview`'s lists | Gate 2 |
| `52-notification-actions-and-widget.md` | D2/R3 — notification actions, the routine widget, a Shortcuts picker | Gate 2 |
| `53-stale-write-guard.md` | N3 — a write built on a pre-rename snapshot duplicates a note | nothing |
| `54-filed-at-record.md` | §10.3 — "captured vs processed" is an approximation | two real weekly reviews |
| `55-incremental-reindex.md` | performance — a commit re-lists and re-assembles the whole vault | nothing |

Three of them (50, 51, 52) are the "still open" items below, now written up properly; the
bullets are kept because they carry the detail of *why* T40/T41 left them.

## Still open

- **T20/T12 duplication, the other half.** `InboxSessionView` implements the card drag geometry
  and fly-out itself instead of `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`.
  T41 left it: the two files involved have never been compiled, and `CardTarget`/`KeyMap`/
  `DragResolver` (the GTD semantics, unit-tested) must stay in `FeatureInbox` either way. Do it
  once `scripts/check.sh --app` has been green once. `InboxPreviewData` still duplicates a
  little of `GTDFixtures`; harmless now that `GTDFixtures` is a declared dependency.
- **⌘F reaches only `FeatureOverview`'s lists** (T25 note #2). `\.overviewQuery` is internal to
  that target; `NextView`/`WaitingView`/`ProjectsListView` cannot read it. Wiring them means
  promoting the environment key into `DesignSystem` — four blind files, so T41 declined.
- **`⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are not in the menu bar** (STYLEGUIDE §4.5, T40 decision #2). They act
  on the focused row and no feature view exposes a focus target to the shell.
- **Notification actions ("Start routine", "Done") and the `ControlWidget`** were skipped (T13,
  T30). The widget needs a widget-extension target `project.yml` does not declare.
- **No `AppEntity` for routines** (T30): `StartRoutineIntent.routine` is a plain `String` matched
  against the title. Fine for two routines; a Shortcuts picker would need the loaded vault.
- **T14's captured/processed stat is an approximation** (no filed-at timestamp in the vault) and
  is documented as such on `WeeklyStats.compute`. T27 presents it honestly; if it reads wrong in
  practice the fix is a persisted filed-at log, which is a vault-format change.
- **T24: a routine run left open across midnight** may re-ask a step logged the previous day —
  a one-log-file-per-day vault-format limitation, documented in the module README.
- **`AppComposition.shutdown()` is never called.** Deliberate; see its doc comment.
- **Everything blind.** `TEST-INSTRUCTIONS.md` → "Where to look first (T41 blind review)" is the
  prioritised list for whoever has a Mac, and its "Unresolved" section holds the judgement calls
  T41 could not make without one (notably `.glassEffect()`'s real shape and `RewardMoment`'s
  `.system(size: 56)` vs STYLEGUIDE §2.3).

## Not done in T41

Nothing from the brief. The two deliverables that cannot be *finished* here are finished as far
as a Linux container can take them, and both say so in the brief's Result: the accessibility pass
is a read-through plus fixes, and `docs/MANUAL_TEST.md` §6 holds what only a device settles; the
performance work measures and fixes what is measurable in a debug build on this machine, and
`agent_task/55-incremental-reindex.md` holds the cost it found but did not remove.

For T42 (done): `docs/TRACEABILITY.md` was the input for `docs/KNOWN_ISSUES.md` (its "Follow-ups" table
and every **partial** row), and the six new briefs must not be archived with the rest of
`agent_task/` — they are work that has not happened yet.
