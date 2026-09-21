#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureWaiting
import GTDFixtures

/// The calendar strip as the Mac list column docks it (D3, STYLEGUIDE §3.10): the same 14 days
/// and the same markers as `FeatureWaiting.CalendarStrip`, laid out for a *narrow* column.
///
/// - Content-sized: a day is its label over one row of markers, so the strip is ~70 pt tall and
///   never grows a flexible spacer.
/// - Scrolls horizontally instead of dividing the column width by 15, which is what wrapped the
///   day labels letter by letter.
/// - Every marker is a `stripMarkerHitSize` (24 pt) click target.
///
/// All data and the signal thresholds come from `WaitingListModel`; this view decides nothing.
struct OverviewCalendarStrip: View {
    var days = 14
    let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let list = WaitingListModel(model: model)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.s) {
                let overdue = list.overduePile
                if !overdue.isEmpty {
                    column(
                        list, label: OverviewMacCopy.overdue, entries: overdue,
                        labelColor: .signal(.overdue), isToday: false)
                    Divider()
                }
                ForEach(Array(list.timeline(days: days).enumerated()), id: \.offset) { _, column in
                    let isToday = column.day == list.today
                    self.column(
                        list,
                        label: OverviewMacCopy.stripDayLabel(column.day, today: list.today),
                        entries: column.entries,
                        labelColor: isToday ? .ink : .textSecondary,
                        isToday: isToday)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.surfaceCard, in: Radius.tileShape)
        .padding(.horizontal, Spacing.m)
    }

    private func column(
        _ list: WaitingListModel,
        label: String,
        entries: [Rules.TimelineEntry],
        labelColor: Color,
        isToday: Bool
    ) -> some View {
        let shown = entries.prefix(OverviewLayout.stripMarkersPerDay)
        return VStack(spacing: Spacing.xs) {
            Text(label)
                .font(Typo.counter)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                    marker(list, entry)
                }
                if entries.count > shown.count {
                    Text(OverviewMacCopy.more(entries.count - shown.count))
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minHeight: OverviewLayout.stripMarkerHitSize)
        }
        .frame(minWidth: OverviewLayout.stripDayMinWidth)
        .padding(.bottom, Spacing.xs)
        .overlay(alignment: .bottom) {
            if isToday {
                Rectangle().fill(Color.gtdAccent).frame(height: 2)
            }
        }
    }

    private func marker(_ list: WaitingListModel, _ entry: Rules.TimelineEntry) -> some View {
        Button {
            onOpen(entry.action)
        } label: {
            Image(systemName: symbol(entry.kind))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(markerColor(list.signalStep(for: entry)))
                .frame(
                    width: OverviewLayout.stripMarkerHitSize,
                    height: OverviewLayout.stripMarkerHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.title)
        .accessibilityLabel(entry.title)
    }

    private func symbol(_ kind: Rules.TimelineKind) -> String {
        switch kind {
        case .deferred: Symbols.deferred
        case .due: Symbols.due
        case .followUp: Symbols.waiting
        }
    }

    /// `nil` (no signal applies) stays `textSecondary` — plain, untinted (STYLEGUIDE §2.1).
    private func markerColor(_ step: SignalStep?) -> Color {
        switch step {
        case nil: .textSecondary
        case .neutral: .signal(.neutral)
        case .aging: .signal(.aging)
        case .attention: .signal(.attention)
        case .overdue: .signal(.overdue)
        }
    }
}

#Preview("Calendar strip · narrow") {
    OverviewCalendarStrip(onOpen: { _ in })
        .frame(width: 380)
        .padding(.vertical)
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
