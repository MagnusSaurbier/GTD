import Foundation
import GTDModel

// The pure calendar arithmetic behind the SwiftUI `DayPicker` (`Components/DayPicker.swift`).
// The app's own grid replaced the stock graphical `DatePicker`, whose single click never reached
// the chip's binding on macOS — picking a day now writes the value on the first click.
// Foundation-only (`Day` is proleptic-Gregorian integer math), so it is unit-tested on Linux.

/// One month laid out as whole ISO weeks: six rows of seven `Day`s, Monday first, padded with
/// the neighbouring months' days so every row is full.
public struct MonthGrid: Sendable, Equatable {
    public let year: Int
    public let month: Int
    /// Six rows of seven days, Monday … Sunday. Days outside `month` are the leading/trailing
    /// padding — `contains(_:)` tells them apart.
    public let weeks: [[Day]]

    /// Always six rows, so the grid never changes height as the user pages through months.
    public static let rowCount = 6
    public static let columnCount = 7

    public init(year: Int, month: Int) {
        let normalized = MonthGrid.normalize(year: year, month: month)
        self.year = normalized.year
        self.month = normalized.month
        let first = Day(year: self.year, month: self.month, day: 1)
        let start = first.startOfISOWeek
        self.weeks = (0..<MonthGrid.rowCount).map { row in
            (0..<MonthGrid.columnCount).map { column in
                start.adding(days: row * MonthGrid.columnCount + column)
            }
        }
    }

    /// The grid holding `day`.
    public init(containing day: Day) {
        self.init(year: day.year, month: day.month)
    }

    /// `true` when `day` belongs to this month rather than to the padding around it.
    public func contains(_ day: Day) -> Bool { day.year == year && day.month == month }

    public var previous: MonthGrid { MonthGrid(year: year, month: month - 1) }
    public var next: MonthGrid { MonthGrid(year: year, month: month + 1) }

    /// `Sep 2026` — the picker's header.
    public var title: String { "\(DateText.months[month - 1]) \(year)" }

    /// `September 2026` — what VoiceOver reads (STYLEGUIDE §8).
    public var spelledTitle: String { "\(MonthGrid.spelledMonths[month - 1]) \(year)" }

    /// `Mo Tu We Th Fr Sa Su` — the column headings, Monday first like `Day.isoWeekday`.
    public static let weekdayInitials = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    public static let spelledMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// Month 0 is the previous year's December, month 13 the next year's January — so `previous`
    /// and `next` need no special case at the year boundary.
    private static func normalize(year: Int, month: Int) -> (year: Int, month: Int) {
        let zeroBased = month - 1
        let yearShift = Int(floor(Double(zeroBased) / 12))
        return (year + yearShift, zeroBased - yearShift * 12 + 1)
    }
}
