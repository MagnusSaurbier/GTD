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

**Status: done.** `scripts/check.sh` passes (see tail below); 27 new tests in
`GTDNotificationsTests`, all passing.

### What was built

- `NotificationPlanner.plan(snapshot:now:calendar:settings:)` — pure. Plans `deferReturn`
  (morning of `deferDate`), `dueApproaching` (morning of `due - 1` **and** morning of `due`),
  `followUp` (morning of `followUpDate`, only for `status == .waiting`), `routineStart`
  (daily-repeating trigger at the routine's own `time`). `done`/`trash` actions are never
  considered; a fire date at or before `now` is dropped. Non-routine notifications that land on
  the exact same instant (same morning) collapse into one `.summary` unless `.summary` itself is
  disabled in settings. Stable ids: `"<kind>:<note path>[:<day>]"`. Ordering/cap: routines first,
  then soonest fire date first, truncated to `maxPending` (64).
- `NotificationScheduler.requestAuthorization()` added (delegates to the port) alongside the
  existing `sync(planned:)` diff, which was already correct as T00 left it.
- `SystemNotificationCenter` (`Sources/GTDNotifications/SystemNotificationCenter.swift`) — the
  real `UNUserNotificationCenter` adapter behind `NotificationCenterPort`, entirely inside
  `#if canImport(UserNotifications)`. Uses `UNCalendarNotificationTrigger` throughout: full
  date-matching components for one-shot notifications, hour/minute-only matching with
  `repeats: true` for routines.
- Test suite: `NotificationPlannerTests` (a hand-computed pass over
  `GTDFixtures.sampleSnapshot`; past-date filtering; done/trash exclusion; the collapse rule and
  its settings toggle; per-kind settings; routine repetition; id stability across re-planning;
  the 64-cap ordering with 145 candidates; DST spring-forward and fall-back plus a fixed
  UTC+5:30 zone, all built on explicit `TimeZone` values per the brief, not `.current`),
  `NotificationSchedulerTests` (add/remove delta, no-op re-sync, authorization pass-through, all
  against a fake actor-based `NotificationCenterPort`), `NotificationRouteTests` (deep-link round
  trip, moved out of T00's placeholder).

### Deviations / additions

- Added `NotificationScheduler.requestAuthorization()`. Not in ARCHITECTURE §4 (which does not
  enumerate `NotificationScheduler`'s members), but the brief lists "authorisation request" as
  part of the scheduler's job and `NotificationCenterPort` already declares it — this only wires
  it through. No contract change needed since `GTDNotifications`'s internal API is owned by T13.
- Notification actions ("Start routine", "Done") were **not** implemented — the brief marks them
  optional stretch, and doing them properly needs `UNNotificationAction`/category registration
  wiring in the app shell (T40), which is out of scope here.

### Files that could not be compiled/verified on Linux

`Packages/GTDKit/Sources/GTDNotifications/SystemNotificationCenter.swift` — entirely guarded by
`#if canImport(UserNotifications)`, written blind. On a Mac, check: it compiles against the
`UserNotifications` framework; `UNCalendarNotificationTrigger(dateMatching:repeats:)` with only
`.hour`/`.minute` set actually fires daily as intended for routines; the `async throws` overloads
of `add(_:)` / `requestAuthorization(options:)` / `pendingNotificationRequests()` resolve (they
are iOS 16+/macOS 13+, well under this app's iOS 26/macOS 26 minimum, so this is low-risk).

### Known limitation (per Acceptance)

A device only knows what has synced into its local `VaultSnapshot` — it has no way to see a
change made on another device until its own next sync. `T40` must call
`NotificationPlanner.plan` + `NotificationScheduler.sync` again on every snapshot change and on
background refresh, not just once at launch; this is noted in the module README.

### `scripts/check.sh` (tail)

```
=== docs check
checking backticked paths in CLAUDE.md README.md
checking the build-out phase marker
  ok (marker and agent_task/ agree)
check-docs.sh: ok

=== xcodebuild — package for the iOS Simulator
SKIPPED: xcodebuild not available (Linux). Asset and string catalogs are compiled by Xcode's build system only — verify this step on a Mac.

=== check.sh finished
```
Full `swift build` and `swift test` (all 470+ package tests, all targets) passed before this;
`GTDNotificationsTests` specifically: 27/27 passed.
