# GTDStats

Weekly review numbers and the routine audit heatmap, computed on the fly from a snapshot — nothing is persisted. Public types: `WeeklyStats`, `RoutineAudit`, `ISOWeek`.

**Owned by T14** — T00 created only the public signatures listed in `docs/ARCHITECTURE.md` §4
so that dependants compile. The bodies throw `notImplemented` or return empty values.

## Platform guards (ARCHITECTURE §5)

Foundation-only, no SwiftUI. Week maths uses `Day.isoWeek` / `Day.startOfISOWeek` (integer arithmetic), not `Calendar`, so year-boundary weeks behave the same everywhere.

## Testing

`cd Packages/GTDKit && swift test --filter GTDStatsTests`
