# T13 — Local notifications (`GTDNotifications`)

**Wave 1 · needs T00**

## Model recommendation

**Difficulty:** Medium · **Recommended model:** Sonnet

The core is a pure, fully specified planner function with deterministic tests; the scheduler is a thin diff over a protocol-wrapped `UNUserNotificationCenter`. Watch items for review: DST/time-zone tests actually exercised, the 64-request cap ordering.

## Goal

Compute and schedule all local notifications from a `VaultSnapshot`.

## Requirements covered

D2, R3, W2 (follow-ups), D1.

## Owns

`Sources/GTDNotifications/`, `Tests/GTDNotificationsTests/`.

## Deliverables

- `NotificationPlanner.plan(snapshot:now:calendar:settings:) -> [PlannedNotification]` — **pure**:
  - deferred item resurfaces (morning of `deferDate`, default 08:00),
  - due approaching (day before + morning of `due`),
  - waiting follow-up due (morning of `followUpDate`),
  - routine start at the routine's `time` (repeating daily trigger).
  Stable identifiers derived from `NoteID` + kind so re-planning is idempotent.
  Respect the iOS limit of 64 pending requests: routines first, then soonest first; same-morning
  items collapse into one summary notification ("3 items came back today").
- `NotificationScheduler` (wraps `UNUserNotificationCenter` behind a protocol for tests):
  authorisation request, `sync(planned:)` = diff against pending requests, add/remove only the delta.
- Deep-link payloads (`gtd://routine/<id>`, `gtd://action/<path>`, `gtd://waiting`) + a
  `NotificationRoute` parser T40 can use. Notification actions: "Start routine", "Done" (complete
  action) are optional stretch — only if trivial.
- `DeviceNotificationSettings` (device-local, not in the vault): per-kind on/off, morning time.

## Acceptance

- Planner fully unit-tested (time zones, DST change day, past dates ignored, 64-cap, collapse rule, completed/trashed items never planned).
- Scheduler diff tested with a fake centre.
- Known limitation documented in code + Result: a device only knows what has synced; T40 re-plans on every snapshot change and on background refresh.

## Result

_(fill in when done)_
