# GTDIntents

App Intents for capture and routines, plus the Shortcuts recipes (`Shortcuts/README.md`).
Requirements: C1, C2, C3 (C4 out of scope), R3.

## Public API

Linux-testable (Foundation-only):
- `CaptureRequest` — normalises text (rejects empty/whitespace-only, trims, keeps line breaks)
  and routes to `GTDVault.InboxWriter`; `perform(writer:now:) throws(CaptureError)`.
- `CaptureError` — `.emptyText`, `.noVaultSelected`, `.bookmarkStale`, `.writeFailed(String)`;
  conforms to `LocalizedError` so a thrown one is a usable spoken/visible message on its own.
- `CaptureStamp` — the `yyyy-MM-dd HHmmss` file-name format, hand-written (locale/platform-free).
- `RoutineDeepLink` / `InboxDeepLink` — build the `gtd://routine/<id>` / `gtd://inbox` strings
  `StartRoutineIntent` / `ProcessInboxIntent` hand to `PendingRoute`.
- `PendingRoute` (+ `PendingRouteStore`, `InMemoryPendingRouteStore`, `UserDefaultsPendingRouteStore`)
  — where a background-launched intent leaves "where the app should navigate once foregrounded";
  see its doc comment for why (`openAppWhenRun` carries no payload, and this app has no separate
  App Intents extension). The shell `consume()`s it on launch and on every foreground, alongside
  its existing `onOpenURL`/`NotificationRoute` handling.

`#if canImport(AppIntents)` (`CaptureIntents.swift`, unverified — no Xcode here):
`CaptureToInboxIntent(text:)`, `StartRoutineIntent(routine:)`, `ProcessInboxIntent`,
`GTDAppShortcuts: AppShortcutsProvider`.

## Platform guards (ARCHITECTURE §5)

All AppIntents machinery lives in `CaptureIntents.swift`, guarded entirely by
`#if canImport(AppIntents)`. Everything worth unit-testing (`CaptureRequest`, `CaptureError`,
`CaptureStamp`, `RoutineDeepLink`, `InboxDeepLink`, `PendingRoute`) is Foundation-only and lives
outside that guard, so `swift test` covers it without Xcode.

## Gotchas

- **`CaptureError.bookmarkStale` is currently unreachable through `InboxWriter`.**
  `VaultBookmark.startAccess()` does `try? resolve()`, so a stale/corrupt bookmark and a
  never-picked one both come out as `VaultError.noVaultSelected`. `.noVaultSelected`'s message is
  worded to cover both; `.bookmarkStale` is kept for if/when `GTDVault` starts distinguishing them.
- **`RoutineDeepLink` assumes `VaultLayout.default`** — the intent has no loaded `GTDConfig` (it
  must not load/index the vault), so a vault with a customised `routines` folder gets a path that
  won't resolve; the shell's `AppRoute` falls back to matching by title.
- **Unverified on a Mac (device subtlety flagged by the brief):** whether
  `CaptureToInboxIntent.perform()` can resolve the security-scoped bookmark and write with the app
  fully suspended, not just backgrounded — this project has no separate App Intents extension.
  See `Shortcuts/README.md` §B.
- Control Center / Lock Screen `ControlWidget` was **not** built: it needs its own widget
  extension target, which `project.yml` doesn't declare — `docs/follow-ups/52-notification-actions-and-widget.md`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDIntentsTests` — 22 tests. The `NoteCodec.decodeInboxItem`
round-trip suite (`CaptureCodecRoundTripTests`) self-gates on a local `codecIsImplemented` probe
(mirroring `GTDVaultTests`), which the finished codec satisfies, so they run.
