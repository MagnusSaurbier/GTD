import Foundation

/// A calendar day without a time zone.
///
/// All arithmetic is proleptic-Gregorian integer math (Howard Hinnant's `days_from_civil` /
/// `civil_from_days`), so `Day` behaves identically on every platform and never depends on
/// Apple-only Foundation APIs. `Calendar` is only involved where a `Day` meets a real `Date`
/// (`init(_:calendar:)`, `startOfDay(in:)`, `date(at:in:)`).
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: Serial (days since 1970-01-01)

    /// Days since 1970-01-01. Negative before that date.
    public var serial: Int { Day.daysFromCivil(year, month, day) }

    public init(serial: Int) {
        let (y, m, d) = Day.civilFromDays(serial)
        self.init(year: y, month: m, day: d)
    }

    // MARK: Dates

    /// The calendar day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Today in the current calendar. Usable as a `() -> Day` value (`AppModel.today`).
    public static func today() -> Day { Day(Date()) }

    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func date(at time: DayTime, in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: time.hour, minute: time.minute))
    }

    // MARK: ISO strings

    /// `yyyy-MM-dd`. Years outside 0…9999 are still zero-padded to four digits.
    public var iso: String {
        let y = year < 0 ? "-" + Day.pad(-year, 4) : Day.pad(year, 4)
        return "\(y)-\(Day.pad(month, 2))-\(Day.pad(day, 2))"
    }

    /// Parses `yyyy-MM-dd`, tolerating a trailing time (`2026-09-19T08:00:00+02:00`).
    public init?(iso: String) {
        let head = String(iso.prefix(while: { $0 != "T" && $0 != " " }))
        let parts = head.split(separator: "-", omittingEmptySubsequences: false)
        // Leading "-" for negative years produces an empty first part.
        let negative = parts.first?.isEmpty == true
        let fields = negative ? Array(parts.dropFirst()) : Array(parts)
        guard fields.count == 3,
              let y = Int(fields[0]), let m = Int(fields[1]), let d = Int(fields[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.init(year: negative ? -y : y, month: m, day: d)
    }

    public var description: String { iso }

    // MARK: Arithmetic

    public func adding(days: Int) -> Day { Day(serial: serial + days) }

    /// Signed number of days from `other` to `self` (`later.days(since: earlier) > 0`).
    public func days(since other: Day) -> Int { serial - other.serial }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    public var isoWeekday: Int { ((serial % 7) + 7 + 3) % 7 + 1 }

    /// The Monday of this day's ISO week.
    public var startOfISOWeek: Day { adding(days: 1 - isoWeekday) }

    /// ISO-8601 week number and its week-based year (the `KW` of `GTD/Reviews/<yyyy>/KW <ww>.md`).
    public var isoWeek: (year: Int, week: Int) {
        let thursday = adding(days: 4 - isoWeekday)
        let jan1 = Day(year: thursday.year, month: 1, day: 1)
        return (thursday.year, (thursday.serial - jan1.serial) / 7 + 1)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Civil-calendar math

    private static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                          // [0, 399]
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1 // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                  // [0, 146096]
        return era * 146097 + doe - 719468
    }

    private static func civilFromDays(_ serial: Int) -> (Int, Int, Int) {
        let z = serial + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097                                       // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365  // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)                // [0, 365]
        let mp = (5 * doy + 2) / 153                                     // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                             // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)                                  // [1, 12]
        return (y + (m <= 2 ? 1 : 0), m, d)
    }
}

/// A time of day without a date — a routine's scheduled start (`time: "07:00"`) or a
/// notification's morning hour.
public struct DayTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses `HH:mm` (and the `HH:mm:ss` YAML sometimes writes).
    public init?(hhmm: String) {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        self.init(hour: h, minute: m)
    }

    public var hhmm: String {
        let h = hour < 10 ? "0\(hour)" : "\(hour)"
        let m = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(h):\(m)"
    }

    public var description: String { hhmm }

    /// Minutes since midnight.
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: DayTime, rhs: DayTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
