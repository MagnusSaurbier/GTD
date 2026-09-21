import Foundation
import GTDModel
import GTDStats
import DesignSystem

/// One `StatTile`'s content (STYLEGUIDE §3.10), as plain data so the §10.3 numbers and their
/// wording are unit-tested instead of assembled inside a view.
public struct ReviewStatTile: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    /// `▲ 3 vs last week`. Never coloured (§3.10).
    public var trend: String?

    public init(id: String, label: String, value: String, trend: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.trend = trend
    }
}

/// A heatmap cell, platform-free. `DesignSystem.HeatmapCellState` lives behind
/// `#if canImport(SwiftUI)`, so the mapping from a `RoutineAudit` happens here and the view
/// only translates the last step.
public enum ReviewHeatmapCell: Sendable, Equatable {
    case done
    case skipped
    case noData
}

/// One heatmap row (= one routine step) plus its completion percentage.
public struct ReviewHeatmapRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var cells: [ReviewHeatmapCell]
    public var completionPercent: Int

    public init(id: String, title: String, cells: [ReviewHeatmapCell], completionPercent: Int) {
        self.id = id
        self.title = title
        self.cells = cells
        self.completionPercent = completionPercent
    }
}

/// The whole audit for one routine, ready to render.
public struct ReviewHeatmap: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var rows: [ReviewHeatmapRow]
    public var columnLabels: [String]
    public var completion: String
    /// `▲ 6 points vs last week`, or `nil` when there is no prior week to compare with.
    public var trend: String?

    public init(
        id: String, title: String, symbol: String, rows: [ReviewHeatmapRow],
        columnLabels: [String], completion: String, trend: String?
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.rows = rows
        self.columnLabels = columnLabels
        self.completion = completion
        self.trend = trend
    }
}

/// Turns `GTDStats` output into what the systems-check screen shows (§10.3).
///
/// The captured/processed pair is presented as the approximation it is: `WeeklyStats` derives it
/// from `created` dates alone because the vault stores no filed-at timestamp, so it cannot see an
/// item that was captured earlier and filed this week, nor one filed into `Knowledge` or trashed
/// (GTDStats README). The tiles keep the numbers — they answer "does the inbox move" — and
/// `ReviewCopy.capturedApproximation` is shown beside them rather than letting them read as an
/// audit trail (§1 "no lying UI").
public enum ReviewStats {

    /// The seven tiles of §10.3, in reading order. `previous` is the same computation for the
    /// prior ISO week and only drives trend lines; without it the tiles simply carry no trend.
    public static func tiles(_ stats: WeeklyStats, previous: WeeklyStats? = nil) -> [ReviewStatTile] {
        [
            ReviewStatTile(
                id: "captured", label: ReviewCopy.statCaptured, value: "\(stats.captured)",
                trend: previous.map { ReviewCopy.trend(stats.captured - $0.captured) }),
            ReviewStatTile(
                id: "processed", label: ReviewCopy.statProcessed, value: "\(stats.processed)",
                trend: previous.map { ReviewCopy.trend(stats.processed - $0.processed) }),
            ReviewStatTile(
                id: "done", label: ReviewCopy.statDone, value: "\(stats.doneThisWeek)",
                trend: previous.map { ReviewCopy.trend(stats.doneThisWeek - $0.doneThisWeek) }),
            ReviewStatTile(
                id: "nextAge", label: ReviewCopy.statNextAge,
                value: ReviewCopy.days(stats.medianNextAgeDays),
                trend: previous.map { ReviewCopy.trend(stats.medianNextAgeDays - $0.medianNextAgeDays) }),
            ReviewStatTile(
                id: "untouched", label: ReviewCopy.statUntouched, value: "\(stats.untouchedOver30Days)",
                trend: previous.map { ReviewCopy.trend(stats.untouchedOver30Days - $0.untouchedOver30Days) }),
            ReviewStatTile(
                id: "waiting", label: ReviewCopy.statWaiting, value: "\(stats.waitingByAgeDays.count)",
                trend: previous.map { ReviewCopy.trend(stats.waitingByAgeDays.count - $0.waitingByAgeDays.count) }),
            ReviewStatTile(
                id: "stalled", label: ReviewCopy.statStalled, value: "\(stats.stalledProjects)",
                trend: previous.map { ReviewCopy.trend(stats.stalledProjects - $0.stalledProjects) }),
        ]
    }

    /// One heatmap per routine (§10.3): rows = steps, 7 columns = days, completion % per row,
    /// trend versus the previous seven days.
    public static func heatmaps(_ audits: [RoutineAudit]) -> [ReviewHeatmap] {
        audits.map { audit in
            ReviewHeatmap(
                id: audit.routine.path,
                title: audit.title,
                symbol: Symbols.routine(title: audit.title),
                rows: audit.rows.map(row(_:)),
                columnLabels: columnLabels(for: audit),
                completion: ReviewCopy.percent(audit.completionPercent),
                trend: ReviewCopy.trend(audit.trend, unit: "points"))
        }
    }

    static func row(_ row: RoutineAudit.Row) -> ReviewHeatmapRow {
        ReviewHeatmapRow(
            id: row.stepID,
            title: row.title,
            cells: row.cells.map(cell(_:)),
            completionPercent: row.completionPercent)
    }

    /// A missing log entry is `noData`, never a silent "skipped": the app does not know what
    /// happened on a day nobody opened the routine (§1 "no lying defaults").
    static func cell(_ cell: RoutineAudit.Cell) -> ReviewHeatmapCell {
        switch cell.result {
        case .done: .done
        case .skipped: .skipped
        case nil: .noData
        }
    }

    /// Weekday initials for the seven columns the audit actually covers — derived from each
    /// cell's `Day`, so a 7-day window that does not start on a Monday still labels correctly.
    public static func columnLabels(for audit: RoutineAudit) -> [String] {
        guard let first = audit.rows.first else { return ReviewCopy.weekdayInitials }
        return first.cells.map { ReviewCopy.weekdayInitials[$0.day.isoWeekday - 1] }
    }
}
