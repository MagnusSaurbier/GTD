# GTDNotifications

Local notification planning and scheduling (D2, R3). Public types: `NotificationPlanner` (pure), `NotificationScheduler`, `NotificationCenterPort`, `PlannedNotification`, `NotificationKind`, `NotificationRoute`, `DeviceNotificationSettings`.

**Owned by T13** — T00 created only the public signatures listed in `docs/ARCHITECTURE.md` §4
so that dependants compile. The bodies throw `notImplemented` or return empty values.

## Platform guards (ARCHITECTURE §5)

The planner and the route parser are Foundation-only and fully unit-tested on Linux. `UNUserNotificationCenter` lives behind `NotificationCenterPort` in a file wrapped entirely in `#if canImport(UserNotifications)`.

## Testing

`cd Packages/GTDKit && swift test --filter GTDNotificationsTests`
