#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// Step 3 (§10.3): three short prompts next to the live numbers and the routine audit.
/// Stat tiles and the heatmap are `DesignSystem` components (STYLEGUIDE §3.10); everything
/// they show comes from `ReviewStats`, so no number is formatted inside a view.
struct SystemsCheckStep: View {
    @Bindable var session: ReviewSession

    private let tileColumns = [GridItem(.adaptive(minimum: 160), spacing: Spacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ReviewStepHeader(title: ReviewCopy.stageSystemsCheck, symbol: ReviewSymbols.review)

            stats
            prompts
            routineAudit
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: Spacing.m) {
                ForEach(session.statTiles) { tile in
                    StatTile(label: tile.label, value: tile.value, trend: tile.trend)
                }
            }
            // The captured/processed pair cannot be exact without a filed-at timestamp; say so
            // rather than letting two numbers imply an audit trail (§1 "no lying UI").
            Text(ReviewCopy.capturedApproximation)
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ForEach(SystemsCheckPrompt.allCases) { prompt in
                ReviewTextField(
                    label: prompt.prompt,
                    placeholder: "",
                    text: Binding(
                        get: { session.systemsCheck[prompt] },
                        set: { session.systemsCheck[prompt] = $0 }))
            }
        }
    }

    @ViewBuilder private var routineAudit: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(ReviewCopy.routineAuditTitle).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            if session.heatmaps.isEmpty {
                ContentUnavailableView(
                    ReviewCopy.noRoutinesTitle,
                    systemImage: Symbols.routineGeneric,
                    description: Text(ReviewCopy.noRoutinesBody))
            } else {
                ForEach(session.heatmaps) { heatmap in
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Label(heatmap.title, systemImage: heatmap.symbol)
                                .font(Typo.sectionHeader)
                                .foregroundStyle(Color.ink)
                            Text(heatmap.completion)
                                .font(Typo.counter)
                                .foregroundStyle(Color.textSecondary)
                            if let trend = heatmap.trend {
                                Text(trend)
                                    .font(Typo.counter)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer(minLength: Spacing.s)
                        }
                        RoutineHeatmap(
                            rows: heatmap.rows.map { row in
                                RoutineHeatmap.Row(
                                    title: row.title,
                                    cells: row.cells.map(Self.cellState),
                                    completionPercent: row.completionPercent)
                            },
                            columnLabels: heatmap.columnLabels)
                        legend
                    }
                    .padding(Spacing.m)
                    .background(Color.surfaceCard, in: Radius.tileShape)
                }
            }
        }
    }

    /// Colour is never the only carrier (STYLEGUIDE §1.6): the legend spells the three cell
    /// states out in words underneath every heatmap.
    private var legend: some View {
        HStack(spacing: Spacing.l) {
            ForEach(
                [ReviewCopy.heatmapLegendDone,
                 ReviewCopy.heatmapLegendSkipped,
                 ReviewCopy.heatmapLegendNoData],
                id: \.self
            ) { label in
                Text(label).font(Typo.counter).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private static func cellState(_ cell: ReviewHeatmapCell) -> HeatmapCellState {
        switch cell {
        case .done: .done
        case .skipped: .skipped
        case .noData: .noData
        }
    }
}
#endif
