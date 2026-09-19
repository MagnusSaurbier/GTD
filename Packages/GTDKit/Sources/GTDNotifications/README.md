# GTDNotifications

Local notification planning and scheduling (D2, R3, W2, D1). Public types: `NotificationPlanner`
(pure), `NotificationScheduler`, `NotificationCenterPort`, `SystemNotificationCenter`,
`PlannedNotification`, `NotificationKind`, `NotificationRoute`, `DeviceNotificationSettings`.

## How it works

- `NotificationPlanner.plan(snapshot:now:calendar:settings:)` is pure: `VaultSnapshot` in,
  `[PlannedNotification]` out. Plans `deferReturn` (morning of `deferDate`), `dueApproaching`
  (morning of `due - 1` **and** morning of `due`), `followUp` (morning of `followUpDate`, only
  for `status == .waiting`), `routineStart` (daily-repeating, at the routine's own `time`, not
  the morning time). `done`/`trash` actions are never planned; a fire date at or before `now` is
  dropped ("past dates ignored"). Non-routine notifications landing on the exact same instant
  collapse into one `.summary` (unless `.summary` is disabled). Ids are
  `"<kind>:<note path>[:<day>]"` — stable across re-planning. Capped at
  `NotificationPlanner.maxPending` (64): routines first, then soonest fire date first.
- `NotificationScheduler` wraps any `NotificationCenterPort`: `requestAuthorization()` delegates
  to the port; `sync(planned:)` diffs `planned` against `pendingIdentifiers()`, adds/removes only
  the delta.
- `SystemNotificationCenter` is the real `UNUserNotificationCenter` adapter.
- `NotificationRoute` parses `gtd://routine/<id>`, `gtd://action/<path>`, `gtd://waiting` back
  out of a `deepLink` (the shell uses this on tap).

**Known limitation:** a device only knows what has synced into its `VaultSnapshot`. The shell
re-plan (`plan` + `sync`) on every snapshot change and on background refresh, not just once.

## Platform guards (ARCHITECTURE §5)

`NotificationPlanner.swift` is Foundation-only, fully unit-tested on Linux.
`SystemNotificationCenter.swift` is wrapped entirely in `#if canImport(UserNotifications)`,
written blind (no Xcode here) — **verify on a Mac**: it compiles, `UNCalendarNotificationTrigger`
with only `.hour`/`.minute` repeats daily as intended, and the `async throws` overloads of
`add`/`requestAuthorization`/`pendingNotificationRequests` resolve (iOS 16+/macOS 13+, so fine
on this app's iOS 26/macOS 26 minimum).

## Testing

`cd Packages/GTDKit && swift test --filter GTDNotificationsTests` — DST spring-forward/fall-back
and a fixed-offset zone (explicit `TimeZone`s), past dates, done/trash, collapse, per-kind
settings, the 64-cap ordering, a full pass over `GTDFixtures.sampleSnapshot`; scheduler diffing
against a fake port; deep-link round trip.
