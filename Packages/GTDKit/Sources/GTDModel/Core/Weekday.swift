import Foundation

/// A day of the week — a routine's optional `day:` (only prompted on that weekday).
///
/// Raw values are ISO weekdays (1 = Monday … 7 = Sunday), matching `Day.isoWeekday`.
public enum Weekday: Int, CaseIterable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Parses an English weekday name, case-insensitive: the full name (`Sunday`) or its
    /// three-letter abbreviation (`Sun`). Surrounding whitespace is ignored.
    public init?(name: String) {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Weekday.allCases.first(where: {
            $0.name.lowercased() == key || $0.name.lowercased().prefix(3) == key && key.count == 3
        }) else { return nil }
        self = match
    }

    /// The full English name, as written to the vault (`Sunday`).
    public var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// `Calendar`'s numbering (1 = Sunday … 7 = Saturday), for `DateComponents.weekday`.
    public var gregorianWeekday: Int { rawValue % 7 + 1 }

    public var description: String { name }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Day {
    /// The weekday this day falls on.
    public var weekday: Weekday { Weekday(rawValue: isoWeekday)! }
}
