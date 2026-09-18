# T40 — App integration (`App/`, `project.yml`)

**Wave 3 · needs everything merged**

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
- **iPhone shell (N5):** tabs/home with **Next (on-the-go)**, **Inbox** (count + Process button →
  full-screen `InboxProcessingView`), **Routines**; quick-capture button; no full task overview.
  Action detail reachable from Next rows. Settings behind a gear.
- **Mac shell:** `OverviewView` as the main window, `Settings` scene, menu commands, weekly review
  as its own full-window mode with `ReviewResumeBanner`.
- **Prompt host:** present `AppModel.prompt` → `WhatsNextSheet` / `ConvertToProjectSheet`.
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
- Manual test script for the user in `docs/MANUAL_TEST.md` covering real-vault, two-device sync and notification checks.
- Verified in the iOS Simulator with screenshots attached to Result.

## Result

_(fill in when done)_
