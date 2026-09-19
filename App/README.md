# App (the shell)

The `GTD` target: `@main`, the composition root and the platform split (N5). No GTD semantics
live here — the shell composes modules and routes between them. Owned by T40.

## Files

| File | What it does |
| --- | --- |
| `GTDApp.swift` | `@main`. Scenes: `WindowGroup` → `RootView`; macOS `Settings` scene and `OverviewCommands` in the menu bar; iOS `backgroundTask(.appRefresh)`. |
| `AppComposition.swift` | Bookmark → `FileVaultStore` → `VaultBackend` → `AppModel`. Onboarding, change-vault, foreground rescan, daily archive, quick capture. `-useFixtures` swaps the chain for `InMemoryBackend` + `GTDFixtures`. |
| `AppRouter.swift` | Where the app is looking: iPhone tab + pushed detail, the one `OverviewNavigation` the Mac window and the menu bar share, and the flows the shell presents. |
| `AppRoute.swift` | One parser for every deep link: `gtd://routine/<id>`, `gtd://action/<path>`, `gtd://waiting` (`NotificationRoute`) and `gtd://inbox` (`InboxDeepLink`). Resolves a routine by title when the path was built from another layout. |
| `RootView.swift` | Phase switch (loading / onboarding / shell), global flows (`WhatsNextSheet`, quick capture, routine runner, error alert) and the lifecycle wiring. |
| `PhoneShell.swift` | iOS only: the three tabs, the processing cover, the settings sheet, the shell's undo toast. |
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
  see. The environment carries it plus `\.vaultRootPath` (for "Open in Obsidian").
- **Deep links:** `onOpenURL`, a notification tap and `PendingRoute().consume()` (launch **and**
  every foreground) all go through `AppRouter.apply(url:)`.
- **Notifications:** every snapshot change re-plans (debounced), as does foregrounding and the
  background refresh — a device only knows what has synced into its own snapshot.
- **Errors:** `AppModel.lastError` and shell failures share one alert. Nothing is swallowed.

## What to verify on a Mac (everything here is compiled blind)

1. `scripts/check.sh --app` — macOS app builds; then build for an iPhone simulator.
2. Run with `-useFixtures` on both platforms: three tabs on iPhone, sidebar/list/detail on Mac.
3. Pick a **copy** of a vault (never the real one): onboarding → counts → relaunch reopens it
   without asking (Gate 3 in `TEST-INSTRUCTIONS.md`).
4. Menu bar: `⌘1…7`, `⌘N` (capture sheet), `⌘I` (processing), `⌘Z`. `⌘,` opens Settings.
5. A notification tap opens the right screen; `xcrun simctl openurl booted gtd://inbox` too.
6. **App Intents:** `GTDIntents` lives in the package, and App Intents metadata is extracted per
   target. If the three shortcuts do not appear in the Shortcuts app, move `CaptureIntents.swift`
   into this target (or add an App Intents extension) — nothing else depends on where it lives.
7. Signing: `DEVELOPMENT_TEAM` in `project.yml` is empty. macOS and the simulator build
   unsigned; for a device, set your team there or in Xcode → Signing & Capabilities.

## Known gaps

- `⌘⏎`, `⌘⇧N/B/M`, `⌘⇧W` (STYLEGUIDE §4.5) act on the focused row and are not in the menu bar:
  the feature views own them and none of them exposes a focus target to the shell yet.
- Quick capture is disabled under `-useFixtures` (there is no file system to write to).
- The weekly review is the `Review` sidebar section (STYLEGUIDE §4.1), not a separate window.
