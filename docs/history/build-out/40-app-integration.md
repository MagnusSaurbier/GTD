# T40 — App integration (`App/`, `project.yml`)

**Wave 3 · needs everything merged**

## Model recommendation

**Difficulty:** Hard · **Recommended model:** Opus

Integration is where mismatched assumptions between 18 independently built modules surface. Needs whole-codebase understanding, lifecycle/entitlement/background-task knowledge, UI tests on two platforms and simulator verification, and the judgment to fix glue problems minimally instead of rewriting modules.

## Goal

Compose the modules into the shipping iOS + macOS app.

## Requirements covered

N1, N5 (device split), N6, D2, R3, E2, E3, P5/A2 prompt presentation, I7.

## Owns

`App/`, `project.yml`, app-level tests/UI tests. Small glue fixes in other targets are allowed if listed in Result.

## Deliverables

- **Composition root:** launch → resolve `VaultBookmark` → none/stale: `OnboardingView` →
  `FileVaultStore` → `VaultBackend` → `AppModel` in the environment. Debug launch argument
  `-useFixtures` runs on `InMemoryBackend` (used by UI tests and screenshots).
- Shell structure, keyboard map and menu commands follow STYLEGUIDE §4 (three tabs, `fullScreenCover` for processing/routines, gear on Next; Mac `⌘` map in §4.5 mirrored in stock `Commands`).
- **iPhone shell (N5):** tabs/home with **Next (on-the-go)**, **Inbox** (count + Process button →
  full-screen `InboxProcessingView`), **Routines**; quick-capture button; no full task overview.
  Action detail reachable from Next rows. Settings behind a gear.
- **Mac shell:** `OverviewView` as the main window, `Settings` scene, menu commands, weekly review
  as its own full-window mode with `ReviewResumeBanner`.
- **Prompt host:** present `AppModel.prompt` → `WhatsNextSheet` (A2's `ConvertToProjectSheet` is opened by the inline button in the views, not by a prompt).
  Global handling of `GTDError` fallthroughs (alert with the message).
- **Quick capture → immediate processing (I7):** capture writes to inbox, then opens processing on that card.
- **Notifications:** request permission (after onboarding), re-plan via `NotificationPlanner` +
  `NotificationScheduler` on every snapshot change (debounced) and in a `BGAppRefreshTask`;
  handle taps via `NotificationRoute` and `gtd://` URLs (`onOpenURL`).
- **Lifecycle:** refresh snapshot on foreground; stop/start security-scoped access correctly;
  daily `archiveCompleted`.
- **Project config:** entitlements (macOS sandbox + user-selected read-write + app-scope
  bookmarks, per T01's report), Info.plist (`BGTaskSchedulerPermittedIdentifiers`, URL scheme
  `gtd`, `UIFileSharingEnabled` not needed), App Intents metadata, app icon placeholder, signing
  left to the user's team (document in README).

## Acceptance

- `scripts/check.sh --app` builds macOS and iOS-simulator apps.
- UI tests with `-useFixtures`: (iOS) process two inbox cards by button, tick off a Next item,
  undo, run a routine to the end; (macOS) sidebar navigation, process a card by keyboard, complete
  a project action → "What's next?" appears.
- `CLAUDE.md` "Commands" and `README.md` updated with verified run instructions: launching on macOS and in the iOS Simulator, `-useFixtures`, running UI tests, signing setup.
- Manual test script for the user in `docs/MANUAL_TEST.md` covering real-vault, two-device sync and notification checks.
- Verified in the iOS Simulator with screenshots attached to Result.

## Result

**Status: done** for everything that can be done without Xcode. `scripts/check.sh` exits 0 (815
tests). Every file in `App/` is compiled **blind** — the acceptance items that need a real
toolchain (`--app` build, UI-test runs, simulator screenshots) are listed under "Not done here".

### What was built (`App/`, 10 files + `App/README.md`)

- **Composition root** (`AppComposition.swift`): launch → `VaultBookmark` → `FileVaultStore` →
  `VaultBackend.start()` (folder skeleton, first scan, watcher, daily archive) → a fresh
  `AppModel` swapped into the environment. No bookmark, or one that no longer resolves →
  `OnboardingView`, with the reason shown rather than swallowed. The picked folder is saved and
  the vault opens **while onboarding is still on screen**, so its validation step shows real
  counts; `onFinished` takes it down (contract change T40-1). `Settings → Change vault…` tears
  the store down, clears the bookmark and goes back to onboarding. Security-scoped access is
  started once per open vault and stopped in `teardown()`; quick capture uses its **own**
  `VaultBookmark` instance so its start/stop pair cannot close the app's.
  `-useFixtures` replaces the whole chain with `InMemoryBackend` + `Fixtures.sampleSnapshot`
  (UI tests, screenshots, and every `#Preview` — a preview can never touch the real vault).
- **Routing** (`AppRoute.swift`, `AppRouter.swift`): one parser for every source —
  `NotificationRoute`'s three links plus `gtd://inbox` (`InboxDeepLink`, T30's missing case).
  `PendingRoute().consume()` runs at launch **and** on every foreground, alongside `onOpenURL`
  and notification taps. A routine link resolves by path first and by **title** second (T30
  gotcha #3). `prune(against:)` drops navigation to notes that left the vault.
- **iPhone shell** (`PhoneShell.swift`, N5/§4.2): three tabs — Next (`.onTheGo`) with the gear and
  quick capture, Inbox (badge + `InboxStartButton` + read-only captures), Routines. Processing is
  a `fullScreenCover`; action detail pushes `ActionDetailView`; settings and the vault-issue list
  are sheets. The shell's `UndoToast` shows only on tabs that do not bring their own (T21's Next
  has one).
- **Mac shell** (`MacShell.swift`, E3/§4.1): `ReviewResumeBanner` above `OverviewView(navigation:)`,
  minimum 900×560, a `Settings` scene (`⌘,`), and `OverviewCommands` in the menu bar sharing the
  **same** `OverviewNavigation` (T25's note). `isCaptureRequested` (`⌘N`) is observed and turned
  into the capture sheet; a processing request from a deep link is handed to the window's own
  sheet instead of being presented twice.
- **Global flows** (`RootView.swift`): `WhatsNextSheet` on `AppModel.prompt` (P5), quick capture →
  write → open processing on that card (I7), a deep-linked `RoutineRunnerView`, and one alert
  fed by both `AppModel.lastError` and shell failures (`GTDError` gets the same wording the
  feature views use).
- **Notifications** (`NotificationService.swift`, `BackgroundRefresh.swift`): `plan` + `sync` on
  **every** snapshot change (2 s debounce), on foreground, and in a `BGAppRefreshTask` (iOS);
  authorization requested once after onboarding and never when already decided; taps routed from
  `userInfo["deepLink"]` through `UNUserNotificationCenterDelegate`. `DeviceSettings` →
  `DeviceNotificationSettings` mapping lives in one tested function.
- **`project.yml`**: `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: [fetch]`, the
  `gtd` URL scheme (kept), source excludes so the generated `Info.plist`/entitlements are not
  also copied as resources, and two new targets — `GTDTests` (`AppTests/`, 11 unit tests for
  routes, router, device id, settings mapping) and `GTDUITests` (`AppUITests/`, launch-and-navigate
  smoke tests that always pass `-useFixtures`) — plus a scheme that builds and tests both.
  Entitlements unchanged (sandbox + user-selected read-write + app-scope bookmarks); no iCloud
  entitlement is needed because the vault is reached through a user-picked folder (ARCHITECTURE §6).

### The flaky test (fixed properly, not skipped)

`FeatureOverviewTests.ActionEditModelTests.aSnapshotArrivingMidEditClobbersNeitherSide` failed
~4 runs in 10 (reproduced here). It was **not** a test problem: the debounced autosave built its
`updateAction` payload from `AppModel.snapshot` *before* another command that was already in
flight had landed, so the save wrote that command's fields back. Fixed in `GTDAppCore.AppModel`
(contract change **T40-2**): commands are serialised in call order, and the new
`send(deriving:)` builds its command only when its turn comes. `ActionEditModel` uses it. 10/10
runs green afterwards; three new tests in `GTDAppCoreTests/CommandOrderTests.swift` pin the
ordering, the nil-cancels case and call order.

### Contract changes

| # | File | Change |
| --- | --- | --- |
| T40-1 | `Packages/GTDKit/Sources/FeatureSettings/SettingsViews.swift` | `OnboardingView(onVaultPicked:onFinished:)` — optional, defaulted, so the frozen one-argument form still compiles. Without it onboarding is a dead end: only the shell can take it down. Module README updated. |
| T40-2 | `Packages/GTDKit/Sources/GTDAppCore/AppModel.swift` | Commands serialised; new `send(deriving:)` (ARCHITECTURE §4 + §6 row). `FeatureOverview/ActionEditModel.swift` adopts it. Both module READMEs updated. |

Other shared files touched: `docs/ARCHITECTURE.md` (§2 layout, §4 contract, §6 three rows),
`CLAUDE.md` (paths + Mac run commands), `README.md` (status, run, layout),
`TEST-INSTRUCTIONS.md` (Gate 2 rewritten to match the wiring; Gate 3 step 1),
`agent_task/ORCHESTRATOR-NOTES.md` (one line: the flaky test is fixed).
New: `docs/MANUAL_TEST.md` (real-vault-on-a-copy, two-device sync, notification and
capture-latency script), `App/README.md`.

### Deviations and decisions (the user could not be asked)

1. **Weekly review is the `Review` sidebar section**, not a separate full-window mode as this
   brief asked: STYLEGUIDE §4.1 lists it in the sidebar, and the style guide wins (ARCHITECTURE
   §5). `ReviewResumeBanner` sits above the window so an interrupted review is always one click
   away. Recorded in ARCHITECTURE §6.
2. **`⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` (§4.5) are not in the menu bar.** They act on the focused row, and no
   feature view exposes a focus target to the shell; putting dead menu items there would be a
   lying UI. Listed in `App/README.md` "Known gaps" for T41.
3. **UI tests are smoke tests, not the four acceptance scenarios.** The feature views carry no
   accessibility identifiers (they were written blind), so scripted taps would be guesswork. The
   scenarios are written out step by step in `docs/MANUAL_TEST.md`; turn them into tests once the
   identifiers are confirmed on a Mac.
4. **Quick capture is disabled under `-useFixtures`** (there is no file system to write to), so
   that one path is manual-test-only.
5. **`gtd://waiting` on iPhone** opens the Next tab: N5 gives the phone no waiting list, and its
   chase items live in Next.
6. **App Intents metadata** is not guessed at: `GTDIntents` lives in the package, and if the three
   shortcuts do not appear in the Shortcuts app the fix (move `CaptureIntents.swift` into the app
   target, or add an App Intents extension) is written down in `App/README.md` rather than a build
   setting nobody here could verify. Same for the `ControlWidget` T30 skipped — it needs a widget
   extension target, still not declared.
7. **Daily `archiveCompleted`** runs at `VaultBackend.start()` (T16) *and* on the first foreground
   of each new day, so a Mac left open for a week still archives.

### Files that could not be compiled on Linux (verify on a Mac)

**All of `App/`** (`GTDApp`, `AppComposition`, `AppRouter`, `AppRoute`, `AppSupport`,
`BackgroundRefresh`, `NotificationService`, `RootView`, `PhoneShell`, `MacShell`) plus
`AppTests/AppShellTests.swift` and `AppUITests/ShellSmokeUITests.swift`. They parse cleanly with
`swiftc -parse` in **both** platform branches (`#if os(iOS)` and `#if os(macOS)` were substituted
and each side parsed), which is not a type-check. Highest-risk spots, in order:

1. `.backgroundTask(.appRefresh(_:))` on the `WindowGroup` (iOS only here) and the `#if` inside
   the `Scene` builder chain.
2. `UNUserNotificationCenterDelegate` under Swift 6 strict concurrency — the delegate is
   `@unchecked Sendable` with a comment, and hops to the main actor through a method, not a
   closure capture.
3. `@Bindable` in a `ViewModifier`, and the `.environment(...)` being outermost so `GlobalFlows`
   and `Lifecycle` can read the model (they read it from `AppComposition` instead, deliberately).
4. `flowCover(item:)` / `flowCover(isPresented:)` — `fullScreenCover` on iOS, `sheet` on Mac.
5. `TabView` + `.tabItem` + `.badge` on iOS 26 (the classic form, not the new `Tab` type).
6. Two presentations in a row (capture sheet → processing cover); there is a 350 ms gap and a
   comment explaining why.
7. `ProgressView(_:)`, `.controlSize`, `ContentUnavailableView`, `.navigationBarTitleDisplayMode`.

The package-side edits (`AppModel.swift`, `ActionEditModel.swift`, `SettingsViews.swift`'s new
parameter) all compile and are tested on Linux, except `SettingsViews.swift` itself, which was
already blind (T26).

### Not done here (needs a Mac — `TEST-INSTRUCTIONS.md` Gate 2)

- `scripts/check.sh --app` (xcodegen + macOS and iOS-simulator app builds).
- Running `AppTests` / `AppUITests`, and the four scripted acceptance scenarios.
- Simulator screenshots for this Result.

### `scripts/check.sh`

```
=== swift build (Packages/GTDKit)
[11 expected "no rule to process file … xcstrings/assetcatalog" warnings]
Build complete!

=== swift test (Packages/GTDKit)
✔ 815 tests across all targets passed (GTDVaultTests 109, GTDModelTests 134,
  GTDMarkdownTests 108, FeatureReviewTests 76, FeatureProjectsTests 59, FeatureInboxTests 49,
  GTDServicesTests 40, FeatureOverviewTests 39, FeatureSettingsTests 30, GTDStatsTests 32,
  GTDNotificationsTests 27, FeatureNextTests 24, GTDIntentsTests 21, DesignSystemTests 20,
  FeatureWaitingTests 19, FeatureRoutinesTests 15, GTDAppCoreTests 7, GTDFixturesTests 6)

=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```

(exit 0; `FeatureOverviewTests` ran 10 consecutive times green after the T40-2 fix.)
