# Known issues and open work

What is wrong, missing or merely assumed, collected from every build-out task's result and from
`docs/TRACEABILITY.md`. Check this file before filing a bug: most of what looks broken below is
either deliberate or already written up.

## 1. Barely run by hand, and never on a real vault

Everything up to 2026-09-19 was built in a Linux container with Swift but no Xcode: every file
behind `#if canImport(SwiftUI)` / `UserNotifications` / `AppIntents`, all of `App/`, `AppTests/`
and `AppUITests/` was written blind. On 2026-09-19 (Xcode 27) the package, the macOS app and the
iOS-simulator app built, all package tests and the app's own test bundles passed, and the app
launched on fixtures on both platforms.

The 2026-09-21 inbox rework was built on that Mac, so its UI code is compiled — 1 280 package
tests pass and both scratch app builds are warning-free — and parts of it have been driven on
screen: the two-step card's step 1, the opened action card with its asterisk refusal, a swipe to
Next, Trash with its toast, the project picker, the keep card's navbar, the Mac per-step key
legends, the Lists sidebar row and the Settings Keyboard pane. **Everything else is compiled and
unit-tested only, and no real vault has been opened.** `docs/MANUAL_TEST.md` is what to walk
through; §4 of the list below says which surfaces are still unclicked.

This section is not a list of suspected bugs, it is the absence of hands-on testing.
`TEST-INSTRUCTIONS.md` is the script and the log for it: Gate 1 (package builds and tests),
Gate 2 (the app builds, launches and smoke-tests on fixtures), Gate 3 (vault access on a real
device), and a prioritised list of the nine places most likely to break. While that file exists,
its **"Unresolved"** section is the live list of judgement calls that need a Mac or the user;
whoever deletes the file after the log is filled moves whatever is still open into this one.

`docs/TRACEABILITY.md` marks blind-written code **done (blind)** and rework code that compiles but
nobody has watched **done (compiled + unit-tested, not clicked)**; it is the per-requirement view
of the same fact.

## 2. Partly met requirements — each has a brief in `docs/follow-ups/`

| Requirement | What is missing | Brief |
| --- | --- | --- |
| E3 (STYLEGUIDE §4.5) | `⌘⏎`, `⌘⇧W`, `Space` are not in the menu bar: they act on the focused row and no feature view exposes a focus target to the shell. (`⌘⇧N`/`⌘⇧S` shipped in T11, reading `OverviewNavigation.openAction`.) | `50-mac-keyboard-map.md` |
| E1/E3 | `⌘F` filters only `FeatureOverview`'s own lists — `\.overviewQuery` is internal to that target, so `NextView`/`WaitingView`/`ProjectsListView` never see it. Searching in those sections does nothing, silently. | `51-search-across-lists.md` |
| D2/R3 | Notifications carry no actions ("Start routine", "Done"); there is no Control Widget (it needs a widget-extension target `project.yml` does not declare); Shortcuts shows a text field instead of a routine picker. | `52-notification-actions-and-widget.md` |
| N3 | An ordinary command has no staleness guard. A device whose snapshot predates a rename writes the old path and the vault ends up with **two** notes — nothing is lost, but nothing warns either. Pinned by `GTDServicesTests/SyncScenarioTests`. | `53-stale-write-guard.md` |
| §10.3 | "Captured vs processed" in the weekly review is an approximation: the vault records when a note was created and completed, never when it was filed out of the inbox. `WeeklyStats.compute` documents it and the review presents it honestly. | `54-filed-at-record.md` |
| I4/D12 (R-3) | The inbox card, "Make action" and the review deck's `Promote` turn `GTDError.missingFields` into an inline, per-card notice; the action editor's status chip names the fields inline (T11). `⌘⇧N` and "What's next?" still route it through `perform`/`report`, so the **shell's alert** names the fields (`Still missing: Why?, Context, Time`) instead of marking them. Acceptable for v1, and deliberate: the reducer is the single authority either way. | — |
| L1/L3–L5 | `FeatureLists`'s views (`ListsHomeView`/`ListItemsView`/`ListItemEditorView`/`ListsSectionsView`/`MakeActionSheet`) compile warning-free on both scratch app builds, every state has a `#Preview`, and the Mac sidebar's `Lists` row has been seen on screen. Nothing below it has been clicked: the iPhone tab's push stack, the `Done` swipe, `Show done`, the item editor and `Make action`. The models under them (`ListsModel`, `ListItemEditModel`, `MakeActionModel`) are unit-tested. | — `docs/MANUAL_TEST.md` §2 |
| I4b | The Knowledge/List navbar (`DesignSystem.KnowledgeListNavbar`, wired into `InboxProcessingView`) renders correctly — `Knowledge · Read · Watch · Wish · More…` was read off a simulator screen — but **tapping a navbar slot has never been confirmed on screen**: the simulator automation available at the time could not reliably hit that particular button row, though the identical `GlassActionBar` row worked for the step-1 and action-card bars in the same session. The code path is the same `session.take(_:)` those bars use and is covered by `InboxSessionTests`. | — `docs/MANUAL_TEST.md` §1.5 |
| N7/I9 | The Mac per-step legend renders correctly from `KeyBindings` (step 1 and the action card were read off a Mac build). The **full Mac keyboard path has never been driven end to end**: arrows, the single-key commands, `⌘Z` and `⌘↩` were not exercised on screen, because the automation available could click bordered buttons but could not reliably type into the card's borderless `TextField`s. `FeatureInboxTests`/`GTDAppCoreTests` cover the key resolution itself. | — `docs/MANUAL_TEST.md` §1.7 |
| performance | Every command re-lists and re-assembles the whole vault (~235 ms of a 276 ms `setStatus` at 1 000 notes, debug build on Linux). Measured by `scripts/benchmark.sh`. | `55-incremental-reindex.md` |

50, 51 and 52 need Gate 2 green first — all three touch files nobody has compiled.

## 3. Deliberate limitations — do not file these as bugs

- **A project cannot be renamed** in the app: the folder name is the project's identity
  (ARCHITECTURE §6), and `updateProject` refuses a changed title with `.invalid`. Its **area**
  can be changed since R-7 — that moves the project's folder — through the project detail's area
  picker (T11), which surfaces a name collision or a gone area inline rather than swallowing it.
- **Projects a pre-rework vault left directly under `Projects/`** keep working with no area and
  are **never moved automatically** (R-6): moving files nobody asked about is the one thing this
  app does not do. They show up first in the projects list, next to the `Projects/no_area/` ones.
  `docs/MANUAL_TEST.md` §9 asks you to drag them into `Projects/no_area/` yourself — or just give them an
  area in the app, which moves the folder for you.
- **A project in `Projects/no_area/` whose note still says `area:`** is reported as a vault issue
  rather than corrected. Picking an area (or "no area") for it in the app repairs the file and
  the folder in one commit; nothing rewrites it behind your back (ARCHITECTURE §6).
- **A routine run left open across midnight** may re-ask a step logged before midnight: the log
  is one file per day, and a fresh run reads only today's. Every entry still carries its own real
  day, so no log is ever wrong (`FeatureRoutines/README.md`).
- **The Next list is never truncated to the cap.** An over-cap vault must stay repairable;
  `capSignal` shows `17/15`. Since R-2 this is also reachable without hand-editing: a deferred
  Next item comes back on its date into an already full list. Nothing is demoted automatically —
  `NextListModel.showsCapSheet` asks for the `Next is full` sheet once per foreground until the
  user demotes something; `NextView` presents it as `NextCapSheet` (T11: `Demote` buttons +
  `Cancel`, no "send to Someday instead" — STYLEGUIDE §3.6).
- **Legacy tier words stay in the file until the status changes.** A note that still says
  `status: backlog` or `status: maybe` reads as Someday and is *not* rewritten (R-1,
  ARCHITECTURE §6) — deliberate, so nothing in the vault is touched behind the user's back. The
  same holds for a pre-rework `status: trash` note: it stays hidden, and `archiveCompleted`
  moves it to `GTD/Trash/` once it is 30 days old.
- **`InMemoryBackend` undoes one step**, `VaultBackend` twenty. Previews and tests use the first.
- **Quick capture is disabled under `-useFixtures`** — there is no file system to write to.
- **`AppComposition.shutdown()` is never called**, deliberately; see its doc comment.
- **Everything in REQUIREMENTS §12 is absent on purpose** (LLM filing and search, people/CRM,
  energy field, photo and share-sheet capture, Calendar/Reminders sync, project deadlines,
  recurring actions, an in-app routine editor, timers). `docs/TRACEABILITY.md` §12 greps for each
  of them; the check is that nothing implements them by accident.

## 4. Smaller things worth knowing

- **Lists are complete end to end (§5a), but only their Mac sidebar row has been seen running.**
  The domain (folder layout, item note, classifier, the eight commands, the `Rules` queries), the
  Settings sections (add / rename / remove with a `confirmationDialog`; favourites capped at 8,
  "Mac only" past the iPhone's four), the iPhone `Lists` tab and the Mac `Lists` sidebar row with
  its content and detail columns all exist and compile warning-free. What nobody has clicked:
  the iPhone tab's push stack, the `Done` swipe and `Show done`, the item editor, and
  `Make action` from either platform. `docs/TRACEABILITY.md` §5a says the same per ID.
- **`createList` is not undoable, on purpose.** A list is a folder, and the only inverse of
  creating one would be removing a directory — the hard delete this vault never does. ⌘Z after
  creating a list therefore undoes the command *before* it. Same for choosing favourites, which
  is a settings change like any other. An empty folder left behind by a rolled-back commit is
  the same trade (ARCHITECTURE §6).
- **Renaming a list only by capitalisation is refused** (`Read` → `read`). macOS and iOS file
  systems are case-insensitive, so that move would ask the file system to rename a folder onto
  itself. Refusing is the option that cannot lose a note; if it ever matters, the way through is
  two renames.
- **A `.moveFolder` on a real iCloud vault has still never run** (T02's note, unchanged by T03):
  removing and renaming a list are the first two commands that emit one, and both are covered
  only by `PlainFileSystem` and `InMemoryFileSystem` tests here.
- **`InboxProcessingView` still implements its own card drag geometry and fly-out** instead of
  `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. The GTD semantics
  (`InboxExit`, `KeyMap`, `DragResolver`) are unit-tested and stay in `FeatureInbox` either way;
  only the presentation would move. The files compile now, so this is doable whenever the inbox
  views are next opened — it is duplication, not a defect.
- **Only a *command's* rename is followed by the navigation.** The reducer reports a rename in
  `Reduction.renames`, it rides with the snapshot, and the shell remaps before it prunes, so
  editing a title keeps the detail open (ARCHITECTURE §4). Undo replays inverse **file ops**
  rather than a command, and a rename made on another device arrives as a rescan, so neither
  carries a `RenameMap`: in those two cases the open detail still closes, with the note present
  under its other name. Nothing is lost.
- **`FeatureSettings.RoutineTimeRow` seeds its `@State` in `init`**, so a routine time changed on
  another device while Settings is open does not move the picker. Harmless; not a sync bug.
- **The Settings Lists/Favourites sections and the Keyboard pane's rebind flow have not been
  clicked through.** Both scratch app builds are warning-free on macOS and the iOS Simulator, and
  the Keyboard pane's *rendering* (row grouping, key legends) was confirmed by a screenshot on
  fixtures. The Lists section, the remove `confirmationDialog`, the favourites `Menu` and the
  key-recorder's actual capture are compiled, unit-tested and code-reviewed only.
  `docs/TRACEABILITY.md` N7/L2 say the same per requirement; `docs/MANUAL_TEST.md` §3.5 is the
  script for driving them.
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
ambiguous `to-do` actions land in **Someday** with a `reviewReason` (the fallback word is always
`someday` — the script never writes `backlog` or `maybe`, R-1), and imported waiting items have
no follow-up date and no "who" (W1's values are not inventable; since D39 only the date is
required, so the review has one field to fill per item rather than two).

Two more things the rework changed, so expect them in the report: `readlist` notes go straight to
`Lists/Read/` as list items (M1) and the old `04_Maybe` items arrive as plain **inbox captures**
rather than `status: maybe` actions (M2), so they reach you through inbox processing and not
through the deck.
