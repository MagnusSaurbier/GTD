# TEST-INSTRUCTIONS — for a local agent (or human) with Xcode

<!-- ONE-TIME FILE. Delete it (git rm TEST-INSTRUCTIONS.md) once all three gates below have run
     on a Mac, the verification log is filled in and committed, and anything still unresolved has
     been moved into docs/KNOWN_ISSUES.md. Until then, keep the log current — it is the only
     record of what the real toolchain said. -->

## Why this file exists

This app was written by agents in a **Linux container with Swift 6.4 and no Xcode** up to
2026-09-19. Everything Foundation-only was compiled and unit-tested there. Everything that needs
an Apple SDK (SwiftUI, AppKit/UIKit, UserNotifications, AppIntents, `NSFileCoordinator`,
security-scoped bookmarks, `#Preview`, the app target, the iOS-simulator build) was written
**without ever being compiled**. Your job is to run the real toolchain, report what breaks, and
fix the mechanical things (wrong API names, missing `import`, availability annotations) without
changing behaviour.

**Since 2026-09-21 that is only half true.** The inbox rework
(`docs/inbox-rework/IMPLEMENTATION-GUIDE.md`) was built on a Mac with Xcode 27, so its UI code
compiles and some of it has been driven on a simulator. Compiling is still not running: the log
at the bottom says exactly what anybody has watched work, and `docs/TRACEABILITY.md` marks the
rest **done (compiled + unit-tested, not clicked)**.

The three gates are the order to do it in. They are about *building and launching*; what to then
check by hand is `docs/MANUAL_TEST.md`, and this file does not repeat it.

Read `CLAUDE.md` first (durable rules, especially: never touch the real Obsidian vault). Then
`docs/ARCHITECTURE.md` §5 "Platform guards" for the `#if canImport(SwiftUI)` convention every
target follows.

## Setup (once)

```sh
brew install xcodegen
cd Packages/GTDKit && swift package resolve && cd ../..
```

## Gate 1 — package builds and tests on macOS

```sh
scripts/check.sh
```

This runs `swift build`, `swift test` in `Packages/GTDKit`, then (now that `xcodebuild` exists)
the iOS-simulator build of the package scheme, then `scripts/check-docs.sh`. On the Mac the
platform-guarded code compiles for the first time, so expect errors. Triage:

| Error class | What to do |
| --- | --- |
| Unknown API / wrong label / missing `import` in a `#if canImport(SwiftUI)` file | Fix in place, minimal edit. |
| Swift 6 strict-concurrency error in UI code (`@MainActor` isolation, non-Sendable capture) | Fix properly (`@MainActor`, `Sendable` value types). No `@unchecked Sendable`, no `nonisolated(unsafe)` unless you write a comment saying why. |
| Missing iOS 26 / macOS 26 API the agent guessed at | Replace with the closest real API; note it in the log below. |
| A test that fails only on macOS | Do **not** disable it. Find out whether the code or the test is wrong; if you cannot, report it verbatim in the log. |
| Resource bundle errors (`Bundle.module`, asset catalog, `Localizable.xcstrings`) | See ARCHITECTURE §5 and `docs/history/build-out/00-foundation.md` "Contract changes"; the intended behaviour is: colours fall back to code-defined values, so a missing catalog must never crash. |

Single target / single test, for iterating:

```sh
cd Packages/GTDKit
swift test --filter GTDModelTests
swift test --filter GTDModelTests.ReducerTests/testNextCapReached   # adjust name
```

### Where to look first (from the blind review)

T41 read every `#if canImport(SwiftUI)` file and all of `App/` without a compiler and fixed what
was clearly wrong. These are the places most likely to break when the real compiler sees them,
**in the order worth trying**. Each one is a whole class of failures: if #1 or #4 breaks, a lot
of files break at once, so fix those before reading any other error.

1. **`DesignSystem/Components/Containers.swift`** — `.glassEffect()` and `GlassEffectContainer { }`
   are the only two APIs in the repo nobody could check the shape of. They sit behind
   `if #available(iOS 26, macOS 26, *)` with a `.ultraThinMaterial` fallback (ARCHITECTURE §6).
   If the call shape is wrong, fix it; if the API is not there at all, delete the `#available`
   branch and keep the fallback, and say so in the log.
2. **`DesignSystem/Tokens/Colors.swift`** — `UIColor(dynamicProvider:)` / `NSColor(name:_:)`
   closures under Swift 6, and the four `NSAppearance.Name` spellings
   (`accessibilityHighContrastAqua` / `…DarkAqua`) that `dynamicContrast` matches on.
3. **`App/GTDApp.swift`** — `.backgroundTask(.appRefresh(_:))` on a `WindowGroup`, the `Settings`
   scene, and the one `#if os(macOS)/#else` that wraps whole scenes (T41 rewrote it; it used to
   be three `#if`s inside a postfix modifier chain).
4. **Global-actor inference in `ViewModifier`s that hold `@Observable` models** —
   `DesignSystem/Interaction/CardSwipeFiling.swift`, `App/RootView.swift`'s `GlobalFlows` and
   `Lifecycle`. They rely on a `ViewModifier` conformance making the whole struct `@MainActor`.
   If that inference does not hold, every one of them errors the same way and the fix is one
   `@MainActor` per struct.
5. **`App/NotificationService.swift`** — `UNUserNotificationCenterDelegate` under strict
   concurrency (`@unchecked Sendable` + a `@MainActor` method hop).
6. **`FeatureInbox/InboxProcessingView.swift`** — `.onKeyPress(characters:phases:)` and
   `KeyPress.modifiers` on macOS, `.sensoryFeedback(.impact(weight:))`, and the two consecutive
   postfix `#if` blocks at the end of `content`'s modifier chain.
7. **`FeatureOverview/OverviewView.swift`** — `NavigationSplitView` three-column init,
   `List(selection:)` + `.tag` in a sectioned sidebar, `.listStyle(.sidebar)`, and
   `@State private var ownedNavigation = OverviewNavigation()` (a `@MainActor` type built in a
   property initialiser).
8. **`FeatureProjects/ProjectViews.swift`** — `OptionArrowShortcut`'s focus-gated
   `.keyboardShortcut`, `List { Section { … } }` mixing header rows with `.onMove` rows.
9. **String/asset catalogs** — the 11 `no rule to process file … xcstrings/assetcatalog`
   warnings are expected under `swift build`; under `xcodebuild` they must compile instead. No
   test asserts on a resolved colour, so a catalog problem must never fail a test.

Behaviours T41 changed blind and could not run — check them in the app, not just the build:

- Inbox processing shows its **card counter, `⌘Z` undo and `Done`** (its toolbar only renders
  because the two presentation sites now wrap it in a `NavigationStack`).
- Inbox zero shows **`RewardMoment`** — bouncing tray with a green check badge, one haptic.
- Waiting → **"Move to Next" while Next is at the cap** shows the error alert instead of doing
  nothing. Same for un-deferring an item that cannot go to Next.
- Mac: **Settings → vault issues sheet closes** with its `Done` button.
- The Next row's context menu has a **`Done`** item (T41's second run added it: it was the one
  swipe action with no keyboard or VoiceOver route).
- The **routine heatmap and the review rail** use `@ScaledMetric`, and `Badge` uses `minHeight`
  instead of a fixed `height`. At the default text size they must look exactly as before; at the
  accessibility sizes they must grow rather than clip. `@ScaledMetric` in these three files is
  new and unverified.
- **`docs/MANUAL_TEST.md` §8.1** is the full accessibility sweep those changes are meant to pass.

## Gate 2 — the app builds and launches

```sh
scripts/check.sh --app       # xcodegen + xcodebuild of the macOS app
open GTD.xcodeproj           # then run the GTD scheme on "My Mac" and on an iPhone simulator
```

The shell is wired: the app resolves a security-scoped bookmark, opens the vault through
`FileVaultStore` + `VaultBackend`, and shows `OnboardingView` when there is no vault yet. The
launch argument **`-useFixtures`** replaces that whole chain with `InMemoryBackend` +
`GTDFixtures.sampleSnapshot` — nothing is read or written on disk. Use it for this gate
(Product → Scheme → Edit Scheme → Arguments → `-useFixtures`).

The gate is: it launches on both platforms without crashing — Mac sidebar · list · detail at a
minimum window of 900×560, iPhone **four** tabs (Inbox · Next · Lists · Routines, opening on
Next). Then **walk `docs/MANUAL_TEST.md` §1–§3**, which is the fixtures checklist: the two-step
inbox card and every one of its exits (§1), Lists (§2), and everything else the 2026-09-21 rework
touched — Someday, the R-2 cap sheet, the optional who, the area picker, Settings and the review
deck (§3). Do not re-derive any of it here.

Two things §1–§3 cannot check from inside the app:

- **Deep links:** `xcrun simctl openurl booted gtd://inbox` starts processing; `gtd://waiting`
  opens the waiting list; `gtd://routine/GTD/Routines/Morning.md` opens that routine's runner.
- **The app's own test bundles:** `AppTests` and `AppUITests` build with the project and run with
  `⌘U`; the UI tests pass `-useFixtures` themselves.

After Gate 3, `docs/MANUAL_TEST.md` §4–§8 are the real-vault (on a **copy**), two-device,
notification, accessibility and performance checks no simulator can cover, and its §9 is the
first-real-use checklist — the only part of this repo meant to touch the actual vault.

## Gate 3 — vault access on device

The device spike was skipped on the user's instruction ("assume the app can read local files"),
so **the app's central assumption has never been tested**: that a security-scoped bookmark to a
user-picked folder inside Obsidian's iCloud container gives durable read/write access
(ARCHITECTURE §6). This gate is that test, and nothing else here matters if it fails.

**Never point the app at the real vault under `~/Library/Mobile Documents/iCloud~md~obsidian/`
while testing** — use a copy of it, or a copy of
`Packages/GTDKit/Sources/GTDFixtures/Resources/SampleVault`.

1. Onboarding (or Settings → "Change vault…") → pick the vault folder (a copy!).
2. Quit and relaunch: the app must reopen the folder from its bookmark without asking again.
3. On iOS: the same two steps, with the vault in the Obsidian iCloud folder via the Files picker.

If step 2 fails on iOS, that is the "no-go" case from
`docs/history/build-out/01-spike-vault-access.md`: record it and stop — the fallback (an
app-owned iCloud container, the vault relocated or symlinked) is a design change for the user.

`docs/MANUAL_TEST.md` §4 is the rest of it: that an outside edit reaches the app, that the app's
own writes leave unknown frontmatter and body sections byte-identical, and that a rename moves
the file and the links together.

## Migration script (independent of Swift)

`scripts/check.sh` runs its 40 tests when a `pytest` is installed. Separately, before anyone
points it at real data:

```sh
cd Tools/migrate
pytest -q                                          # expect 40 passed
python3 migrate.py --vault /path/to/COPY/of/vault  # dry run; read migration-report.md
```

`--vault` is required and the dry run writes only `migration-report.md`. Review
`Tools/migrate/README.md`'s checklist before anyone runs `--apply`, and note that the real run is
the user's to do, step by step, in `docs/MANUAL_TEST.md` §9.

## How to report

Fill in the log below and commit it together with the fixes, on the branch you are working on
(say in the log which one that is). For each fix:
one bullet, file path, one line what was wrong. For each thing you could not fix: the exact error
text in a fenced block and the file/line. Do not refactor, restyle or "improve" code that compiles.

## Verification log

Branch: `claude/sharp-volta-p59pxh`. Machine: macOS 26 (arm64), Xcode 27.0 (27A266a), Swift 6.4,
xcodegen 2.46.0. Run by an agent; the person was away for part of it (see Gate 2 and 3).

| Date | Gate | Result | Notes |
| --- | --- | --- | --- |
| 2026-09-19 | 1 | **pass** | `scripts/check.sh`: `swift build` clean (0 warnings — the 11 `no rule to process` warnings do not appear on a Mac), 851 package tests pass, iOS-simulator `xcodebuild` of the package succeeds, docs check ok. Two compile errors and one script portability bug fixed first (below). None of the nine "where to look first" places broke: `.glassEffect()` / `GlassEffectContainer` exist with the shape used, the colour providers, `GTDApp` scenes, `ViewModifier` actor inference, the notification delegate, `onKeyPress`, `NavigationSplitView` and the catalogs all compiled as written. |
| 2026-09-19 | 2 | **partial pass** | `scripts/check.sh --app` succeeds; macOS and iOS-simulator apps build with no errors or warnings. `GTDTests` 11/11 on macOS and on iPhone 18 Pro (iOS 27.0); `GTDUITests` 4/4 on the simulator (not run on macOS — the screen was locked). **Mac, `-useFixtures`:** launches, sidebar · list · detail, sidebar order and live counts as in MANUAL_TEST §1, `Go` menu navigates, Inbox lists 5 captures (the sixth is parked for the review) with `Process inbox (5)`, `⌘I` opens processing, validation focuses "What?", `Undo`/`Done` render, `Done` closes. **iPhone:** launches, three tabs, inbox badge 5, gear and `+` on Next. **Not checked** (person away, screen locked mid-run): filing cards, undo toast, "What's next?", `⌘1…⌘7`/`⌘N`/`⌘,`, Settings, the cap's forced choice, a routine run, dark mode / Dynamic Type, `RewardMoment`, the Waiting error alert, the Next row's `Done` menu item, the Mac issues sheet, `@ScaledMetric` growth. Deep links: `AppRouteTests`/`AppRouterTests` pass and `simctl openurl gtd://inbox` reaches the app's "Open in GTD?" prompt, which nobody was there to confirm. |
| 2026-09-19 | 3 | **step 1 failed, fixed, retest pending** | The user picked a vault copy (`…/iCloud~md~obsidian/Documents/Magnus_GTD`) in onboarding on the Mac: `could not bookmark: NSCocoaErrorDomain Code=256 "Could not open() the item"`. Cause and fix below (`VaultBookmark.save`). Steps 1–3 still to be re-run with the fix. Step 3 needs a physical iPhone signed into iCloud. Note for whoever runs it: build signed (at least `CODE_SIGN_IDENTITY=-`) — `scripts/check.sh --app` passes `CODE_SIGNING_ALLOWED=NO`, which drops the sandbox entitlements, so that build proves nothing about security-scoped bookmarks. |
| 2026-09-19 | migrate | **pass** | `pytest -q` in `Tools/migrate`: 40 passed (pytest from a throwaway venv). The dry run against a vault copy was not done — it is the user's step. |
| 2026-09-21 | 1 | **pass** | The 2026-09-21 inbox rework (`docs/inbox-rework/IMPLEMENTATION-GUIDE.md`), on `feature/inbox-rework`. `scripts/check.sh`: `swift build` clean, **1 280 package tests pass** (Model 223, Markdown 145, Vault 152, Services 77, AppCore 51, Inbox 111, Review 91, Settings 73, Lists 18, Overview 61, Projects 71, Next 32, Waiting 23, DesignSystem 46, Notifications 28, Stats 33, Intents 22, Routines 17, Fixtures 6), `check-docs.sh` ok, iOS-simulator `xcodebuild` of the package ok. New in this run: `GTDServicesTests/InboxFlowJourneyTests` (6 journeys over the real stack on a temp vault copy) and `FeatureInboxTests/InboxSessionJourneyTests` (4 whole-session journeys). Both were verified to **fail** when R-4's preamble and R-1's tolerant decode were deliberately broken. |
| 2026-09-21 | migrate | **pass** | `"$TMPDIR/gtd-rework/venv/bin/python" -m pytest -q` in `Tools/migrate`: **42 passed** (pytest from a throwaway venv; it is still not on this machine's PATH, so `scripts/check.sh` SKIPs it). The script was never run outside its tests. The dry run against a vault copy remains the user's step — `docs/MANUAL_TEST.md` §9.3. |
| 2026-09-21 | 2 | **partial pass** | Both scratch app builds (macOS + iOS Simulator, own `derivedDataPath`, walkthrough bundle id) are green and warning-free throughout the rework. Driven on screen on fixtures during it: inbox step 1, the opened action card, the required-field refusal with all four asterisks, a swipe to Next with its toast, `Trash` with its toast, the project picker, the Knowledge/List card with its navbar rendered, the Mac per-step key legends, the Mac `Lists` sidebar row, and the Settings Keyboard pane's rendering. **Not driven on screen:** the cap sheet, the `⋯` menu, the Waiting sheet, tapping a navbar slot, the Undo button, the full Mac keyboard path, every Lists flow below the sidebar row, the area picker, the Settings Lists/Favourites sections, an actual rebind, and the whole review deck. `docs/MANUAL_TEST.md` was rewritten for the new flow and is the script for all of it; `docs/TRACEABILITY.md` marks each of those rows **done (compiled + unit-tested, not clicked)**. |
| 2026-09-21 | 3 | **not attempted** | No real vault was opened, by rule. A `.moveFolder` — which removing or renaming a list and changing a project's area all emit — has still never run against a live iCloud vault; it is covered only by `PlainFileSystem`/`InMemoryFileSystem` tests. `docs/MANUAL_TEST.md` §5 is the two-device script for it. |
| 2026-09-21 | 2 (walkthrough) | **pass with gaps** | Manager's click-through on fixtures. **iPhone 18 Pro simulator, seen working:** four tabs with Next selected; Lists home → list → item editor → `Make action` (refusal with four asterisks that clear as fields fill, swipe → Next, item leaves the list, keyboard `Done` works on first presentation); inbox step 1 (three equal neutral buttons, `Defer to review`), card expands in place with focus on `Why?`, `Next is full` sheet (Demote / Cancel only) and demote-and-retry, Waiting sheet (required date, one tap confirms the dashed +7 d, optional who), toast + toolbar Undo returning the *opened* card with its draft (R-9), swipe ↓ collapses, keep card with `Knowledge · Read · Watch · Wish · More…`, a list slot files at once (`Added to Wish`), Knowledge folder picker, `+ defer · + due · + project`. **Mac walkthrough build, seen working:** sidebar order with `Lists`, Lists sections with counts and `Show done`, inbox sheet step 1 and opened action card with per-step legends, `Done` bar while a field is focused, `Done` (2-minute rule) filing. **Found and fixed:** a filing awaited while the view refreshed leaked the filed card's text into the next card (regression test `aRefreshDuringAFilingNeverLeaksTheFiledCardIntoTheNextOne`), plus nine UI defects (commit "fixes from the on-screen walkthrough"). **Not seen by anyone:** the Mac single-key path (`A K X D`, `← →`, `W P`, digits) and a rebind reflected live — background automation cannot deliver letter keys; Mac toast placement after the fix; Settings › Lists/Favourites and the remove-list dialog; Someday list, Waiting rows, project area picker, R-2 cap sheet on a returning deferred item; the review deck; `Defer to review`, `More…`, project picker create-row on this build; VoiceOver, Reduce Motion, AX sizes. `docs/MANUAL_TEST.md` §1–§3 is the script for these. |
| 2026-09-21 | 2 (follow-up) | **built, not seen** | Mac Settings window did not scroll (user report): `SettingsView`'s `Form` had no form style, so macOS used `.columns`, which never scrolls, inside a fixed 520×560 frame. Now `.formStyle(.grouped)` + a min/ideal/max frame and `.windowResizability(.contentSize)` on the `Settings` scene. `scripts/check.sh` green (**1 283 package tests**, docs check ok, iOS-simulator package build ok); the scratch macOS app build (own `derivedDataPath`, walkthrough bundle id) succeeds and launches on `-useFixtures`. **Not verified on screen:** automation access to the walkthrough app was declined, so nobody has opened `⌘,` on this build — `docs/MANUAL_TEST.md` §3.5's first line is the check. |
| 2026-09-21 | 1 (follow-up) | **pass, unseen on screen** | `fix/followup-lists`: first real-vault use found the inbox `More…` sheet empty because `Lists/` had no subfolder. The sheet now ends in `New list…` (creates the list, files the card) and shows `No lists yet` when there is none. `scripts/check.sh`: build clean, **1 289 package tests**, docs check ok, package builds for the iOS Simulator; pytest skipped (not installed). **Not seen by anyone:** the new row, the empty state, focus landing in the name field, the refusal line — `docs/MANUAL_TEST.md` §1.5. |
| 2026-09-22 | 2 (follow-up) | **built, not seen** | `fix/followup-pickers`: on the real vault the inbox `Project` sheet did not scroll — projects past the sheet's bottom edge were unreachable, and `Pick a project` sat as a label in a left column (user screenshot). Cause: the sheet `Form`s had no form style, so macOS used `.columns` (same defect as the Settings window). All four (`KnowledgeSheet`, `ProjectSheet`, `DeferToReviewSheet`, `MakeActionProjectSheet`) are now `DesignSystem.sheetFormStyle()` (grouped + min/ideal Mac sheet frame) with explicit `prompt:` + `.labelsHidden()` fields; the five `List` sheets (`CapSheet`, `MoreListsSheet`, `MakeActionCapSheet`, `NextCapSheet`, the review deck's cap sheet) got `scrollingSheetFrame()`; `WhatsNextSheet`/`ConvertToProjectSheet` scroll long step lists (`OverflowScroll`). iOS unchanged (both frame helpers are no-ops there, grouped is its default). `scripts/check.sh` exit 0: **1 297 package tests**, docs check ok, pytest SKIPPED (not installed), iOS-Simulator package build succeeded; scratch macOS app build (own `derivedDataPath`, walkthrough bundle id) succeeded with 0 warnings. **Not verified on screen** — nothing was launched; the fixtures have too few projects to overflow, so use the new `Project — 40 projects, must scroll` preview or a vault copy. Checks: `docs/MANUAL_TEST.md` §1.3 and §3.4 (last line). |

### Fixes applied

Compile / toolchain (no behaviour change):

- `Packages/GTDKit/Sources/GTDNotifications/SystemNotificationCenter.swift` — `UNUserNotificationCenter` is not `Sendable`, so the `Sendable` struct could not store it; now `@preconcurrency import UserNotifications`, with the reason.
- `Packages/GTDKit/Sources/GTDVault/Platform/CoordinatedFileSystem.swift` — `purposeID: NSObject?` in a `Sendable` struct; now `nonisolated(unsafe)` with a comment (immutable identity token, never read).
- `scripts/check-docs.sh` — used GNU `find -printf`; BSD `find` has none, so every basename lookup failed on a Mac (7 false "MISSING"). Now `-print | sed`.
- `project.yml` — XcodeGen wrote `TEST_HOST = …/GTD.app/GTD` for the multiplatform unit-test target, which does not exist on macOS ("Could not find test host"). Now `$(BUNDLE_EXECUTABLE_FOLDER_PATH)`, right on both platforms.

Found by Gate 3 (vault access):

- `Packages/GTDKit/Sources/GTDVault/VaultBookmark.swift` — `save(url:)` bookmarked the URL from `.fileImporter` without `startAccessingSecurityScopedResource()`, which the sandbox refuses ("Could not open() the item"). It now brackets the bookmark creation with `store.startAccess`/`stopAccess`, as the stale-refresh path already did. Regression test: `savingOpensTheScopeOfAPickedFolderBeforeBookmarkingIt`.

Found by running (presentation only):

- `Packages/GTDKit/Sources/FeatureInbox/InboxProcessingView.swift` — on macOS the card counter never rendered: it is a `.principal` toolbar item and a Mac sheet has no title bar (`Undo` and `Done` do render). On macOS the same `session.counter` text now sits above the card; iOS is untouched. Seen working ("5 of 5 left").

Docs the run made untrue, corrected: `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/KNOWN_ISSUES.md` §1 ("never been compiled", and the 11 warnings being Linux-only).

### Unresolved

**From the 2026-09-19 run**

0. **Fix attempted 2026-09-21 (`fix/followup-esc`), not yet seen on screen.** The user then
   reported the worse half by hand: `Esc` on the opened action card closed the whole sheet. `Esc`
   now comes from a window-scoped `NSEvent` monitor (`FeatureInbox/EscapeKeyMonitor.swift`) plus
   `.interactiveDismissDisabled()`; it compiles and the suite is green, but nobody has pressed
   the key yet — run the "Mac, by hand" `Esc` checks in `docs/MANUAL_TEST.md` §1. Original note:
   Mac inbox processing: once a card text field has focus, `Esc` did not blur it, so the arrow
   keys kept moving the caret instead of filing (`InboxProcessingView.quit()` expects "Esc first
   blurs the field"). A focused `TextField` probably consumes Esc before the container's
   `.onKeyPress(.escape)`. Adding `.onExitCommand` on the container did not help and was reverted.
   **Low confidence:** the keys were sent by an automation tool and it is not proven that its Esc
   reached the app — press Esc by hand before changing anything. Clicking the sheet's empty area
   does not blur the field either.
0a. The unsigned test-host run on macOS logs `connection to service named
   com.apple.linkd.autoShortcut` errors (App Intents registration). Expected without signing;
   check that the three shortcuts appear once the app is signed (App/README.md "App Intents").

Open questions T41 could not settle without a Mac. Nothing here blocks the build; each is a
judgement call someone with the real toolchain (or the user) should make.

**Style guide**

1. `DesignSystem/Components/RewardMoment.swift` uses `.font(.system(size: 56))` for the hero
   symbol. STYLEGUIDE §2.3 says "system text styles only, never `.system(size:)`". Changing it
   blind would change how the only two reward moments in the app look, so it was left alone.
   Decide on a Mac: keep it (and add the exception to §2.3) or move to `.largeTitle` +
   `.imageScale(.large)`.
2. `.sensoryFeedback(.impact(weight:))` is used on both platforms (`CardSwipeFiling`,
   `InboxProcessingView`). If `SensoryFeedback.impact` turns out to be iOS-only, guard those two
   call sites — do not drop the feedback on iOS.
3. `Symbols.checkboxOn/Off` and `Symbols.moveUp/moveDown` are stock SF Symbols with no entry in
   STYLEGUIDE §7's icon map. The map is a vault note, so no agent could edit it; either add the
   four rows there or accept them as stock control affordances.

**Known functional gaps (deliberate, not bugs)**

4. `⌘F` filters only `FeatureOverview`'s own lists. It travels through an **internal**
   `\.overviewQuery` environment value, so `NextView` / `WaitingView` / `ProjectsListView`
   cannot read it. Wiring them means promoting that environment key into `DesignSystem` — a
   shared-file change across four blind files, which T41 judged too risky to do unverified.
5. `⌘⏎`, `⌘⇧N/B/M` and `⌘⇧W` (STYLEGUIDE §4.5) are not in the menu bar: they act on the focused
   row and no feature view exposes a focus target to the shell (T40's decision #2, still open).
6. `FeatureInbox`'s `InboxSessionView` still implements its own drag geometry and fly-out rather
   than `DesignSystem`'s `CardFilingController` + `.cardSwipeFiling`. The GTD semantics
   (`CardTarget`, `KeyMap`, `DragResolver`) are unit-tested here and must stay; only the
   presentation would move. Rewriting a gesture in a file nobody can compile was not worth it —
   do it once the file has built once. The inbox-zero half of that duplication *is* done.
7. `AppComposition.shutdown()` is never called; see its doc comment. Process exit releases the
   security scope, and `scenePhase == .background` is not termination.
8. `FeatureSettings.RoutineTimeRow` seeds `@State` from the routine in `init`, so a routine time
   changed on another device while Settings is open does not move the picker. Harmless; listed
   so it is not mistaken for a sync bug.
9. "Open in Obsidian" (action detail, a project's reference files, Vault issues) is built by
   `GTDAppCore.ObsidianLink`: `path=<absolute path>` on the Mac, `vault=<folder name>&file=…` on
   iOS. Unit-tested only — never clicked against a real vault (`docs/MANUAL_TEST.md` §4).
10. `FeatureProjects`' views materialise their model in `.task` on first appearance. A tap
    between the first render and that task would mutate a throwaway instance (T22's note).
    Watch for it; it should be unreachable in practice.

**Known gaps, already written up — do not file these as bugs**

11. Five of STYLEGUIDE §4.5's shortcuts are not in the menu bar and `⌘F` reaches only the
    overview's own lists. Both have briefs waiting on this gate:
    `docs/follow-ups/50-mac-keyboard-map.md` and `docs/follow-ups/51-search-across-lists.md`.
12. Notifications carry no actions, there is no routine widget, and Shortcuts shows a text field
    instead of a routine picker: `docs/follow-ups/52-notification-actions-and-widget.md`.
13. `docs/TRACEABILITY.md` is the full list of what is and is not implemented, per requirement.
    Check it before concluding something is missing — it may be deliberate.
