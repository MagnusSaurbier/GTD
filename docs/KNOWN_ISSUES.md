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
| I4/D12 (R-3) | Only the inbox card, "Make action" and (T12, 2026-09-21) the review deck's `Promote` turn `GTDError.missingFields` into an inline, per-card notice. The action editor's status chip and "What's next?" still route it through `perform`/`report`, so the **shell's alert** names the fields (`Still missing: Why?, Context, Time`) instead of marking them. Acceptable for v1, and deliberate: the reducer is the single authority either way. | — (T11 refines the remaining two) |
| I2–I4c (T08/T09) | The two-step card's **state machine, keys, legends, picker models and navbar model are done and tested** (`FeatureInbox/InboxSession`), but its **views are not**: `InboxProcessingView`/`InboxCardView`/`InboxSheets` were adapted mechanically so the package builds, not designed. Missing against STYLEGUIDE §3.5/§3.6: the three real bars (`StepOneBar`/`ActionCardBar`/`KnowledgeListNavbar` exist in `DesignSystem` but are not wired), expand-in-place motion with the cross-fade, the asterisks and the shake on the card, the one-time hint's real wording, the step-1 card scrolling its text instead of `Show all` (`InboxSession.Sheet.fullText` still exists for that), VoiceOver custom actions beyond the plain list, the Reduce Motion path, and previews per step × platform. | — (T09) |
| L4 | `FeatureInbox.MakeActionModel` is the card entry point and is tested, but nothing presents it yet: `FeatureLists` does not exist. | — (T10) |
| performance | Every command re-lists and re-assembles the whole vault (~235 ms of a 276 ms `setStatus` at 1 000 notes, debug build on Linux). Measured by `scripts/benchmark.sh`. | `55-incremental-reindex.md` |
| §10.2 (R-3) | The review deck's missing-fields notice offers `Edit`, but `FeatureReview` has no editor of its own (ARCHITECTURE §2: `FeatureOverview` depends on it, not the reverse) — `WeeklyReviewView(onEditAction:)` is a real hook `ReviewDeckViews` calls, defaulted to a no-op. The app shell (or `FeatureOverview`, the Mac content router) still has to pass a closure that actually opens the action. Until then, `Edit` clears the inline notice and does nothing else. | — (shell wiring, next UI pass) |

50, 51 and 52 need Gate 2 green first — all three touch files nobody has compiled.

## 3. Deliberate limitations — do not file these as bugs

- **A project cannot be renamed** in the app: the folder name is the project's identity
  (ARCHITECTURE §6), and `updateProject` refuses a changed title with `.invalid`. Its **area**
  can be changed since R-7 — that moves the project's folder — but no view offers it yet (T11),
  so today it is reachable only through `ProjectDetailModel.setArea(_:)`.
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
  user demotes something (the sheet itself is wired in T11).
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

- **Lists have a domain but no UI yet (§5a).** T03 built the whole Lists domain — the folder
  layout, the item note, the classifier, the eight commands and the `Rules` queries — and the
  views come with T10 (the iPhone tab and the Mac sidebar row) and T13 (settings: add, rename,
  remove, favourites). Until then nothing in the app can create a list, file a capture into one
  or check an item off, and a user who makes `Lists/Read/` by hand in Obsidian gets a vault the
  app reads correctly and cannot yet show. `docs/TRACEABILITY.md` §5a says the same per ID.
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
- **`InboxSessionView` still implements its own card drag geometry and fly-out** instead of
  `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. The GTD semantics
  (`CardTarget`, `KeyMap`, `DragResolver`) are unit-tested and stay in `FeatureInbox` either way;
  only the presentation would move. Worth doing once those files have compiled at least once.
- **Only a *command's* rename is followed by the navigation.** The reducer reports a rename in
  `Reduction.renames`, it rides with the snapshot, and the shell remaps before it prunes, so
  editing a title keeps the detail open (ARCHITECTURE §4). Undo replays inverse **file ops**
  rather than a command, and a rename made on another device arrives as a rescan, so neither
  carries a `RenameMap`: in those two cases the open detail still closes, with the note present
  under its other name. Nothing is lost.
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
