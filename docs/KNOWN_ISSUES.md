# Known issues and open work

What is wrong, missing or merely assumed, collected from every build-out task's result and from
`docs/TRACEABILITY.md`. Check this file before filing a bug: most of what looks broken below is
either deliberate or already written up.

## 1. Compiled once, barely run, and never on a real vault

The app was built in a Linux container with Swift but no Xcode. Every file behind
`#if canImport(SwiftUI)` / `UserNotifications` / `AppIntents`, all of `App/`, `AppTests/` and
`AppUITests/` was written blind. On 2026-09-19 (Xcode 27) the package, the macOS app and the
iOS-simulator app built, all package tests (852 now) and the app's own test bundles passed, and the app
launched on fixtures on both platforms. **No view has been walked through by hand beyond that, and
no real vault has been opened.**

This is not a list of suspected bugs, it is the absence of hands-on testing. `TEST-INSTRUCTIONS.md`
is the script and the log for it: Gate 1 (package builds and tests), Gate 2 (the app
builds, launches and smoke-tests on fixtures), Gate 3 (vault access on a real device), and a
prioritised list of the nine places most likely to break. While that file exists, its
**"Unresolved"** section is the live list of judgement calls that need a Mac or the user; whoever
deletes the file after the log is filled moves whatever is still open into this one.

`docs/TRACEABILITY.md` marks such code **done (blind)** and is the per-requirement view of the
same fact.

## 2. Partly met requirements — each has a brief in `docs/follow-ups/`

| Requirement | What is missing | Brief |
| --- | --- | --- |
| E3 (STYLEGUIDE §4.5) | `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` are not in the menu bar: they act on the focused row and no feature view exposes a focus target to the shell. | `50-mac-keyboard-map.md` |
| E1/E3 | `⌘F` filters only `FeatureOverview`'s own lists — `\.overviewQuery` is internal to that target, so `NextView`/`WaitingView`/`ProjectsListView` never see it. Searching in those sections does nothing, silently. | `51-search-across-lists.md` |
| D2/R3 | Notifications carry no actions ("Start routine", "Done"); there is no Control Widget (it needs a widget-extension target `project.yml` does not declare); Shortcuts shows a text field instead of a routine picker. | `52-notification-actions-and-widget.md` |
| N3 | An ordinary command has no staleness guard. A device whose snapshot predates a rename writes the old path and the vault ends up with **two** notes — nothing is lost, but nothing warns either. Pinned by `GTDServicesTests/SyncScenarioTests`. | `53-stale-write-guard.md` |
| §10.3 | "Captured vs processed" in the weekly review is an approximation: the vault records when a note was created and completed, never when it was filed out of the inbox. `WeeklyStats.compute` documents it and the review presents it honestly. | `54-filed-at-record.md` |
| performance | Every command re-lists and re-assembles the whole vault (~235 ms of a 276 ms `setStatus` at 1 000 notes, debug build on Linux). Measured by `scripts/benchmark.sh`. | `55-incremental-reindex.md` |

50, 51 and 52 need Gate 2 green first — all three touch files nobody has compiled.

## 3. Deliberate limitations — do not file these as bugs

- **A project cannot be renamed** and its area cannot be changed in the app: the folder is the
  project's identity (ARCHITECTURE §6). `updateProject` refuses it with `.invalid`.
- **A routine run left open across midnight** may re-ask a step logged before midnight: the log
  is one file per day, and a fresh run reads only today's. Every entry still carries its own real
  day, so no log is ever wrong (`FeatureRoutines/README.md`).
- **The Next list is never truncated to the cap.** An over-cap vault must stay repairable;
  `capSignal` shows `17/15`.
- **`InMemoryBackend` undoes one step**, `VaultBackend` twenty. Previews and tests use the first.
- **Quick capture is disabled under `-useFixtures`** — there is no file system to write to.
- **`AppComposition.shutdown()` is never called**, deliberately; see its doc comment.
- **Everything in REQUIREMENTS §12 is absent on purpose** (LLM filing and search, people/CRM,
  energy field, photo and share-sheet capture, Calendar/Reminders sync, project deadlines,
  recurring actions, an in-app routine editor, timers). `docs/TRACEABILITY.md` §12 greps for each
  of them; the check is that nothing implements them by accident.

## 4. Smaller things worth knowing

- **`InboxSessionView` still implements its own card drag geometry and fly-out** instead of
  `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. The GTD semantics
  (`CardTarget`, `KeyMap`, `DragResolver`) are unit-tested and stay in `FeatureInbox` either way;
  only the presentation would move. Worth doing once those files have compiled at least once.
- **`FeatureSettings.RoutineTimeRow` seeds its `@State` in `init`**, so a routine time changed on
  another device while Settings is open does not move the picker. Harmless; not a sync bug.
- **`VaultIssuesView`'s "Open in Obsidian"** builds `obsidian://open?path=<vault-relative path>`.
  That probably needs the vault name or root, which the target cannot resolve by contract.
- **`FeatureProjects`' views materialise their model in `.task` on first appearance.** A tap
  between the first render and that task would mutate a throwaway instance. Should be unreachable
  in practice; watch for it once the app runs.
- **Conflict-copy detection over-reports:** `VaultLayout.actionPath` uses the same " 2" suffix for
  a genuine title collision, so a legitimately named file can be flagged as a conflict copy. An
  issue is only ever a message and the file stays indexed and untouched — the safe direction.
- **`CaptureToInboxIntent` while the app is fully suspended is unverified.** If the OS refuses to
  run it without a launch, `openAppWhenRun` may need to flip to `true`; the Shortcuts recipe A
  path (which writes without the app) stays the app-free capture route either way.
- **The three App Intents may not appear in the Shortcuts app**: `GTDIntents` lives in the package
  and App Intents metadata is extracted per target. `App/README.md` has the fix to try.
- **The staleness thresholds (14 d / 30 d / inbox 7 d / due 3 d / follow-up 2 d) are first
  guesses.** STYLEGUIDE §10 says to tune them after two real weekly reviews, with real data.

## 5. Migration (`Tools/migrate/`)

The script has never been run against a real vault, by design — only the user runs it, against a
copy, after reading a dry-run report. It is dry-run by default, backs up `Actions/`,
`Actions_legacy/`, `Projects/` and `Inbox.md` before `--apply`, refuses to run if the backup
fails, and deletes nothing. Every value it does not recognise (unknown contexts, dangling links,
area-vs-project decisions) is **reported, never guessed** — that report is the safety net, and
working through it is step 3 of `docs/MANUAL_TEST.md` §9.

Two migration outcomes are deliberately incomplete and are settled in the first weekly review:
ambiguous `to-do` actions land in Backlog with a `reviewReason`, and imported waiting items have
no "who" and no follow-up date (W1's values are not inventable).
