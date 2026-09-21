import Foundation
import GTDModel

/// Bridges `DayTime` (hour/minute only) to `Date`, for binding to a stock
/// `DatePicker(displayedComponents: .hourAndMinute)` (routine times, morning time). Only the
/// hour/minute components are meaningful; the date itself is an arbitrary fixed reference so the
/// conversion is deterministic and Linux-testable without touching `Calendar.current`.
public extension DayTime {
    /// Not really part of the public contract; `public` only because a default-argument
    /// expression must be at least as visible as the API it defaults.
    static let referenceCalendar = Calendar(identifier: .gregorian)

    /// A `Date` on a fixed reference day carrying this time of day.
    var asDate: Date {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        return DayTime.referenceCalendar.date(from: components) ?? Date()
    }

    /// Reads back the hour/minute of `date` in `calendar` — the inverse of `asDate`.
    init(_ date: Date, calendar: Calendar = DayTime.referenceCalendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}
