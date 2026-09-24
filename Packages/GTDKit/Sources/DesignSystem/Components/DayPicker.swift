#if canImport(SwiftUI)
import SwiftUI
import GTDModel

/// The app's own month calendar: one click on a day picks it, the way every date control in the
/// app is meant to work (STYLEGUIDE §3.1 — a value is set by the tap that chooses it).
///
/// It replaced the stock `DatePicker(.graphical)` the date chips used to show: inside the chip's
/// popover on macOS, clicking a day never reached the chip's binding, so the date could not be
/// set at all (user report, 2026-09-24). The grid is plain SwiftUI buttons over `MonthGrid`, so
/// the click path is the app's own.
public struct DayPicker: View {
    private let selection: Day?
    private let today: Day
    private let onPick: (Day) -> Void

    @State private var grid: MonthGrid

    /// - Parameters:
    ///   - selection: the day drawn as chosen, if any. `nil` selects nothing and opens the grid
    ///     on `today` — a picker never pre-selects a date nobody chose (§1 "no lying defaults").
    ///   - onPick: called with the day the user clicked. The caller writes the value and closes
    ///     the picker; this view keeps no date of its own.
    public init(selection: Day?, today: Day = Day.today(), onPick: @escaping (Day) -> Void) {
        self.selection = selection
        self.today = today
        self.onPick = onPick
        _grid = State(initialValue: MonthGrid(containing: selection ?? today))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            weekdayHeadings
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.serial) { day in
                        cell(day)
                    }
                }
            }
        }
        .accessibilityLabel(Copy.pickADate)
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Text(grid.title)
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
                .accessibilityLabel(grid.spelledTitle)
            Spacer(minLength: Spacing.s)
            step(Symbols.previousMonth, label: Copy.previousMonth) { grid = grid.previous }
            // Back to the month the user came from — the stock picker's "today" dot, but it
            // only moves the grid; it never picks a date on its own.
            step(Symbols.thisMonth, label: Copy.thisMonth) {
                grid = MonthGrid(containing: selection ?? today)
            }
            step(Symbols.nextMonth, label: Copy.nextMonth) { grid = grid.next }
        }
    }

    private func step(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typo.controlGlyph)
                .foregroundStyle(Color.gtdAccent)
                .frame(width: Spacing.minHitTarget, height: Spacing.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekdayHeadings: some View {
        HStack(spacing: 0) {
            ForEach(MonthGrid.weekdayInitials, id: \.self) { initial in
                Text(initial)
                    .font(Typo.badge)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Self.cellWidth)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: Day) -> some View {
        Button {
            onPick(day)
        } label: {
            Text("\(day.day)")
                .font(Typo.meta)
                .monospacedDigit()
                .foregroundStyle(foreground(day))
                .frame(width: Self.cellWidth, height: Self.cellHeight)
                .background {
                    if day == selection {
                        Circle().fill(Color.gtdAccent).frame(width: Self.cellHeight)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.dayPickerCell(day, today: today))
        .accessibilityAddTraits(day == selection ? [.isSelected] : [])
    }

    private func foreground(_ day: Day) -> Color {
        if day == selection { return .inkInverse }
        if day == today { return .gtdAccent }
        return grid.contains(day) ? .ink : .textTertiary
    }

    private static let cellWidth: CGFloat = 36
    private static let cellHeight: CGFloat = 30
}
#endif
