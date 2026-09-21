# App (the shell)

The `GTD` target: `@main`, the composition root and the platform split (N5). No GTD semantics
live here — the shell composes modules and routes between them. It is outside the Swift package,
so it never compiles on Linux and none of it has ever been built.

## Files

| File | What it does |
| --- | --- |
| `GTDApp.swift` | `@main`. Scenes: `WindowGroup` → `RootView`; macOS `Settings` scene and `OverviewCommands` in the menu bar; iOS `backgroundTask(.appRefresh)`. |
| `AppComposition.swift` | Bookmark → `FileVaultStore` → `VaultBackend` → `AppModel`. Onboarding, change-vault, foreground rescan, daily archive, quick capture. `-useFixtures` swaps the chain for `InMemoryBackend` + `GTDFixtures`. |
| `AppRouter.swift` | Where the app is looking: iPhone tab + pushed detail, the one `OverviewNavigation` the Mac window and the menu bar share, and the flows the shell presents. |
| `AppRoute.swift` | One parser for every deep link: `gtd://routine/<id>`, `gtd://action/<path>`, `gtd://waiting` (`NotificationRoute`) and `gtd://inbox` (`InboxDeepLink`). Resolves a routine by title when the path was built from another layout. |
| `RootView.swift` | Phase switch (loading / onboarding / shell), global flows (`WhatsNextSheet`, quick capture, routine runner, error alert) and the lifecycle wiring. |
| `PhoneShell.swift` | iOS only: the four tabs (Inbox · Next · Lists · Routines, opening on Next), the processing cover, the settings sheet, the shell's undo toast. |
| `MacShell.swift` | macOS only: `ReviewResumeBanner` + `OverviewView(navigation:)`, and the `Settings` scene's content. |
| `NotificationService.swift` | Plan + sync on every snapshot change (2 s debounce), on foreground and in background refresh; permission after onboarding; `UNUserNotificationCenterDelegate` for taps. |
| `BackgroundRefresh.swift` | `BGAppRefreshTaskRequest` scheduling, and the main-actor registry the `@Sendable` background-task closure needs. |
| `AppSupport.swift` | Launch options, the device id (routine-log file names, N3), shell strings, `AppError`. |

`AppTests/` holds unit tests for the four things above that are pure logic; `AppUITests/` holds
launch-and-navigate smoke tests (always `-useFixtures`, never a real vault).

## How it is wired

- **Launch:** `bootstrap()` resolves the security-scoped bookmark. No bookmark (or it no longer
  resolves) → `OnboardingView`; the folder it returns is saved, the vault opens behind it so the
  validation step shows real counts, and `onFinished` takes onboarding down.
- **Snapshots:** `AppModel` is swapped when the vault opens, and it is the only thing features
  see. The environment carries it plus `\.vaultRootPath` (for "Open in Obsidian"; the Mac
  `Settings` scene inherits nothing from `RootView`, so `GTDApp` sets both there too).
- **Renames:** every snapshot change goes to `AppRouter.apply(snapshot:renames:)` with
  `AppModel.consumeRenames()` — `RootView` is the one consumer. A rename moves the note's file
  (A1), so its old `NoteID` leaves the snapshot like a deleted one's; the router therefore
  follows the renamed ids **first** and drops what is still missing after that. The rules are
  `GTDAppCore.NavigationRemap`, tested on Linux; the shell only calls them.
- **Deep links:** `onOpenURL`, a notification tap and `PendingRoute().consume()` (launch **and**
  every foreground) all go through `AppRouter.apply(url:)`.
- **Notifications:** every snapshot change re-plans (debounced), as does foregrounding and the
  background refresh — a device only knows what has synced into its own snapshot.
- **Errors:** `AppModel.lastError` and shell failures share one alert. Nothing is swallowed.

## What to verify on a Mac (everything here is compiled blind)

The order is `TEST-INSTRUCTIONS.md` Gates 1–3, then `docs/MANUAL_TEST.md`; neither is repeated
here. Two things are this target's own, and are not in either:

- **App Intents metadata** is extracted per target. `GTDIntents` lives in the package, so if the
  three shortcuts do not appear in the Shortcuts app, move `CaptureIntents.swift` into this
  target (or add an App Intents extension) — nothing else depends on where it lives.
- **Signing:** `DEVELOPMENT_TEAM` in `project.yml` is empty. macOS and the simulator build
  unsigned; for a device, set your team there or in Xcode → Signing & Capabilities.

## Known gaps

- `⌘⏎`, `⌘⇧N/S`, `⌘⇧W` (STYLEGUIDE §4.5) act on the focused row and are not in the menu bar:
  the feature views own them and none of them exposes a focus target to the shell yet
  (`docs/follow-ups/50-mac-keyboard-map.md`).
- Quick capture is disabled under `-useFixtures` (there is no file system to write to).
- The weekly review is the `Review` sidebar section (STYLEGUIDE §4.1), not a separate window.
- `AppComposition.shutdown()` is deliberately unwired: `scenePhase == .background` is not
  termination (on the Mac it fires when the window is hidden, on iOS the background refresh task
  still needs the vault), and process exit releases the security scope anyway.
- `GTDApp.body` uses **one** `#if os(macOS)/#else` around whole scenes. Do not go back to
  per-modifier `#if`s: a postfix `#if` chain followed by an `#if` that opens a statement is the
  shape a blind-written scene builder most easily gets wrong.
- A presented view that carries its own `.toolbar` needs a `NavigationStack` here —
  `InboxProcessingView` does not wrap itself, because the review wizard embeds it inline.
