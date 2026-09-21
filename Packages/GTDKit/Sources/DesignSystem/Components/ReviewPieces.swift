#if canImport(SwiftUI)
import SwiftUI

// Mac-only review/wizard building blocks (STYLEGUIDE §3.10). Pure presentation — the data comes
// from `GTDStats`/`Rules` in the owning feature (`FeatureReview`, T27); this target never depends
// on `GTDStats` (ARCHITECTURE §2 dependency direction).

/// A review stat tile (STYLEGUIDE §3.10): label on top, a big number, an optional trend line.
/// Trends are never colored — they carry no urgency, just information.
public struct StatTile: View {
    private let label: String
    private let value: String
    private let trend: String?

    public init(label: String, value: String, trend: String? = nil) {
        self.label = label
        self.value = value
        self.trend = trend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(Typo.meta).foregroundStyle(Color.textSecondary)
            Text(value).font(Typo.stat).foregroundStyle(Color.ink)
            if let trend {
                Text(trend).font(Typo.counter).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: Radius.tileShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trend.map { "\(label): \(value), \($0)" } ?? "\(label): \(value)")
    }
}

// `HeatmapCellState` and the words VoiceOver reads for a row live in `HeatmapContent.swift`,
// outside the SwiftUI guard, so they can be unit-tested on Linux.

/// The routine heatmap (STYLEGUIDE §3.10, R5): rows = steps, 7 columns = days. Done cells are
/// `signalDone`; skipped cells are a quiet dot; empty cells are blank. Colour is never the only
/// carrier: each row is one VoiceOver element whose value spells the week out
/// (`HeatmapSpeech.week`), and the grid scales with Dynamic Type.
public struct RoutineHeatmap: View {
    public struct Row: Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public let cells: [HeatmapCellState]
        /// `0...100`.
        public let completionPercent: Int

        public init(title: String, cells: [HeatmapCellState], completionPercent: Int) {
            self.title = title
            self.cells = cells
            self.completionPercent = completionPercent
        }
    }

    private let rows: [Row]
    private let columnLabels: [String]
    private static let cellGap: CGFloat = 3

    /// The grid scales with the text size (STYLEGUIDE §8: Dynamic Type to AX3 without loss of
    /// function). A fixed 120 pt row label truncated the step title at the larger sizes.
    @ScaledMetric(relativeTo: .caption) private var cellSize: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var rowLabelWidth: CGFloat = 120

    public init(rows: [Row], columnLabels: [String]) {
        self.rows = rows
        self.columnLabels = columnLabels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Self.cellGap) {
                Color.clear.frame(width: rowLabelWidth)
                ForEach(columnLabels, id: \.self) { label in
                    Text(label)
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: cellSize)
                }
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)          // the day names are repeated in every row's label
            ForEach(rows) { row in
                HStack(spacing: Self.cellGap) {
                    Text(row.title)
                        .font(Typo.meta)
                        .foregroundStyle(Color.ink)
                        .frame(width: rowLabelWidth, alignment: .leading)
                        .lineLimit(2)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                    Spacer(minLength: Spacing.s)
                    Text("\(row.completionPercent)%")
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title), \(row.completionPercent) percent complete")
                .accessibilityValue(HeatmapSpeech.week(row.cells, columnLabels: columnLabels))
            }
        }
    }

    @ViewBuilder private func cellView(_ state: HeatmapCellState) -> some View {
        RoundedRectangle(cornerRadius: Radius.cell, style: .continuous)
            .fill(fill(for: state))
            .overlay {
                if state == .skipped {
                    Circle().fill(Color.textTertiary).frame(width: cellSize / 4.5, height: cellSize / 4.5)
                }
            }
            .frame(width: cellSize, height: cellSize)
    }

    private func fill(for state: HeatmapCellState) -> Color {
        switch state {
        case .done: .signalDone.opacity(0.85)
        case .skipped, .noData: .fillQuiet
        }
    }
}

/// The four-stage review wizard rail (STYLEGUIDE §3.10): a checkmark for a finished stage, an
/// accent dot for the current one. Resumable — reopening the review shows the same progress.
public struct ReviewWizardRail: View {
    public struct Stage: Identifiable, Sendable {
        public var id: String { title }
        public let title: String
        public let subSteps: [String]
        public let isComplete: Bool

        public init(title: String, subSteps: [String] = [], isComplete: Bool) {
            self.title = title
            self.subSteps = subSteps
            self.isComplete = isComplete
        }
    }

    private let stages: [Stage]
    private let currentStageID: Stage.ID?

    public init(stages: [Stage], current: Stage.ID?) {
        self.stages = stages
        self.currentStageID = current
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ForEach(stages) { stage in
                HStack(alignment: .top, spacing: Spacing.s) {
                    marker(for: stage)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(stage.title)
                            .font(Typo.sectionHeader)
                            .foregroundStyle(stage.id == currentStageID ? Color.ink : Color.textSecondary)
                        ForEach(stage.subSteps, id: \.self) { step in
                            Text(step).font(Typo.meta).foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: stage))
            }
        }
    }

    @ViewBuilder private func marker(for stage: Stage) -> some View {
        if stage.isComplete {
            Image(systemName: Symbols.done)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.signalDone)
        } else if stage.id == currentStageID {
            Circle().fill(Color.gtdAccent).frame(width: 8, height: 8).padding(6)
        } else {
            Circle().strokeBorder(Color.hairline, lineWidth: 1.5).frame(width: 8, height: 8).padding(6)
        }
    }

    private func accessibilityLabel(for stage: Stage) -> String {
        if stage.isComplete { return "\(stage.title), done" }
        if stage.id == currentStageID { return "\(stage.title), current step" }
        return stage.title
    }
}

/// The quiet key-legend row under the Mac inbox card and review deck (STYLEGUIDE §3.6, §3.10):
/// `← Someday  → Next  ↓ Collapse    P Project · K Knowledge · W Waiting · R Review`.
public struct KeyLegendRow: View {
    public struct Entry: Identifiable, Sendable {
        public var id: String { key }
        public let key: String
        public let label: String?

        public init(key: String, label: String? = nil) {
            self.key = key
            self.label = label
        }
    }

    private let entries: [Entry]

    public init(_ entries: [Entry]) {
        self.entries = entries
    }

    public var body: some View {
        HStack(spacing: Spacing.l) {
            ForEach(entries) { entry in
                HStack(spacing: Spacing.xs) {
                    Text(entry.key)
                    if let label = entry.label {
                        Text(label)
                    }
                }
            }
        }
        .font(Typo.counter)
        .foregroundStyle(Color.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entries.map { entry in
            entry.label.map { "\($0): \(entry.key)" } ?? entry.key
        }.joined(separator: ", "))
    }
}
#endif
