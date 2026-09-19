import Testing
import Foundation
import GTDModel
import GTDStats
import GTDFixtures
@testable import FeatureReview

/// The systems-check numbers (§10.3) and how they are worded.
@MainActor
struct ReviewStatsTests {

    @Test func thereIsOneTilePerNumberSection103Asks() {
        let session = ReviewTest.session()
        let ids = session.statTiles.map(\.id)
        #expect(ids == ["captured", "processed", "done", "nextAge", "untouched", "waiting", "stalled"])
        #expect(session.statTiles.allSatisfy { !$0.value.isEmpty })
    }

    @Test func tilesCarryTheNumbersWeeklyStatsComputed() {
        let session = ReviewTest.session()
        let stats = session.stats
        let tiles = Dictionary(uniqueKeysWithValues: session.statTiles.map { ($0.id, $0.value) })
        #expect(tiles["captured"] == "\(stats.captured)")
        #expect(tiles["processed"] == "\(stats.processed)")
        #expect(tiles["done"] == "\(stats.doneThisWeek)")
        #expect(tiles["untouched"] == "\(stats.untouchedOver30Days)")
        #expect(tiles["waiting"] == "\(stats.waitingByAgeDays.count)")
        #expect(tiles["stalled"] == "\(stats.stalledProjects)")
    }

    /// Captured/processed cannot be exact without a filed-at timestamp (GTDStats README), so the
    /// screen says so rather than letting two numbers read as an audit trail.
    @Test func theCapturedApproximationIsStatedInWords() {
        #expect(ReviewCopy.capturedApproximation.contains("approximate"))
        #expect(ReviewCopy.capturedApproximation.contains("Knowledge"))
    }

    @Test func trendsAreWordedWithAnArrowAndNeverColoured() {
        #expect(ReviewCopy.trend(3) == "▲ 3 vs last week")
        #expect(ReviewCopy.trend(-2) == "▼ 2 vs last week")
        #expect(ReviewCopy.trend(0) == "no change vs last week")
        #expect(ReviewCopy.trend(6, unit: "points") == "▲ 6 points vs last week")
        // `ReviewStatTile` carries text only — there is nowhere for a colour to live.
        let tile = ReviewStatTile(id: "x", label: "L", value: "1", trend: ReviewCopy.trend(1))
        #expect(tile.trend == "▲ 1 vs last week")
    }

    @Test func tilesWithoutAPreviousWeekCarryNoTrend() {
        let tiles = ReviewStats.tiles(
            WeeklyStats(year: 2026, week: 38, captured: 4, processed: 2), previous: nil)
        #expect(tiles.allSatisfy { $0.trend == nil })
    }

    @Test func statsAndTheHeatmapDescribeTheSameSevenDays() {
        let session = ReviewTest.session()
        // The review day is the week's last day; `WeeklyStats` anchors on exactly that.
        #expect(session.reviewDay == session.week.days.last)
        let audits = RoutineAudit.compute(
            routines: session.snapshot.routines,
            log: session.snapshot.routineLog,
            endingOn: session.reviewDay)
        let days = audits.first?.rows.first?.cells.map(\.day)
        #expect(days?.last == session.reviewDay)
        #expect(days?.count == 7)
        #expect(days?.first == session.reviewDay.adding(days: -6))
    }

    @Test func heatmapRowsFollowTheRoutineTemplate() throws {
        let session = ReviewTest.session()
        let heatmaps = session.heatmaps
        #expect(heatmaps.count == session.snapshot.routines.count)

        let morning = try #require(heatmaps.first { $0.title == "Morning" })
        let routine = try #require(session.snapshot.routines.first { $0.title == "Morning" })
        #expect(morning.rows.map(\.id) == routine.steps.map(\.id))
        #expect(morning.rows.allSatisfy { $0.cells.count == 7 })
        #expect(morning.columnLabels.count == 7)
        #expect(morning.symbol == "sunrise")
        #expect(morning.completion.hasSuffix("%"))
        #expect(morning.trend != nil)
    }

    /// A day with no log entry is "not logged", never a silent "skipped".
    @Test func cellStatesMapOneToOneAndNeverInventASkip() {
        let day = Fixtures.today
        #expect(ReviewStats.cell(RoutineAudit.Cell(day: day, result: .done)) == .done)
        #expect(ReviewStats.cell(RoutineAudit.Cell(day: day, result: .skipped)) == .skipped)
        #expect(ReviewStats.cell(RoutineAudit.Cell(day: day, result: nil)) == .noData)
    }

    @Test func columnLabelsFollowTheDaysTheAuditActuallyCovers() throws {
        let session = ReviewTest.session()
        let heatmap = try #require(session.heatmaps.first)
        let days = (0..<7).map { session.reviewDay.adding(days: $0 - 6) }
        #expect(heatmap.columnLabels == days.map { ReviewCopy.weekdayInitials[$0.isoWeekday - 1] })
    }

    @Test func anEmptyAuditFallsBackToMondayFirstHeaders() {
        let audit = RoutineAudit(
            routine: NoteID(path: "GTD/Routines/Empty.md"), title: "Empty",
            rows: [], completionPercent: 0, trend: 0)
        #expect(ReviewStats.columnLabels(for: audit) == ReviewCopy.weekdayInitials)
        #expect(ReviewCopy.weekdayInitials.count == 7)
    }

    @Test func aVaultWithoutRoutinesProducesNoHeatmaps() {
        var snapshot = ReviewTest.inboxZero
        snapshot.routines = []
        snapshot.routineLog = []
        #expect(ReviewTest.session(snapshot).heatmaps.isEmpty)
    }
}
