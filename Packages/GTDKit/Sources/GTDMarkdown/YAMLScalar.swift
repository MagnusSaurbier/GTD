import Foundation
import GTDModel

/// Rendering Swift values as YAML scalars, and parsing the date formats found in the vault.
///
/// Deliberately hand-written instead of `Yams.dump` / `ISO8601DateFormatter`:
/// * `Yams.dump` re-serialises a whole mapping and destroys the user's formatting;
/// * `ISO8601DateFormatter` and `DateFormatter` differ subtly between Apple platforms and
///   swift-corelibs-foundation, which would make the round-trip tests platform-dependent.
public enum YAMLScalar {

    // MARK: - Strings

    /// A plain (unquoted) scalar would be misread as something else, or is not representable.
    static func needsQuoting(_ value: String) -> Bool {
        if value.isEmpty { return true }
        if value != value.trimmingCharacters(in: .whitespaces) { return true }
        if value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) { return true }
        if value.contains(": ") || value.hasSuffix(":") { return true }
        if value.contains(" #") { return true }
        // Indicators that start a plain scalar are forbidden.
        if let first = value.first,
           "-?:,[]{}#&*!|>'\"%@`".contains(first) { return true }
        // Anything that would resolve to a non-string type.
        if resolvesToNonString(value) { return true }
        return false
    }

    private static func resolvesToNonString(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let reserved: Set<String> = [
            "true", "false", "yes", "no", "on", "off", "y", "n",
            "null", "~", ".nan", ".inf", "-.inf",
        ]
        if reserved.contains(lowered) { return true }
        if Int(value) != nil || Double(value) != nil { return true }
        // Sexagesimals (YAML 1.1) and dates resolve away from String.
        if value.contains(":") { return true }
        if Day(iso: value) != nil, value.count == 10 { return true }
        return false
    }

    /// A double-quoted YAML scalar with the escapes YAML requires.
    static func quoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// `value` as a scalar, quoted only when it has to be.
    public static func string(_ value: String) -> String {
        needsQuoting(value) ? quoted(value) : value
    }

    /// A flow sequence: `[a, b, c]`. Matches the style the vault already uses.
    public static func flowList(_ values: [String]) -> String {
        "[" + values.map { string($0) }.joined(separator: ", ") + "]"
    }

    // MARK: - Dates

    /// `yyyy-MM-dd`.
    public static func day(_ value: Day) -> String { value.iso }

    /// ISO-8601 with an explicit offset, e.g. `2026-09-18T21:04:11+02:00`.
    public static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 1))-\(pad(c.day ?? 1))T"
            + "\(pad(c.hour ?? 0)):\(pad(c.minute ?? 0)):\(pad(c.second ?? 0))"
            + "\(sign)\(pad(minutes / 60)):\(pad(minutes % 60))"
    }

    private static func pad(_ value: Int, _ width: Int = 2) -> String {
        let negative = value < 0
        var digits = String(abs(value))
        if digits.count < width { digits = String(repeating: "0", count: width - digits.count) + digits }
        return negative ? "-" + digits : digits
    }

    /// Parses the timestamp shapes the vault actually contains.
    ///
    /// Accepted: `yyyy-MM-dd`, `yyyy-MM-ddTHH:mm`, `…THH:mm:ss`, `…THH:mm:ss.SSS`, a space
    /// instead of `T`, and an offset of `Z`, `±HH:mm`, `±HHmm` or `±HH`. A timestamp without an
    /// offset is read in `defaultTimeZone` (TaskNotes wrote local times that way).
    public static func parseTimestamp(_ raw: String, defaultTimeZone: TimeZone) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let scalars = Array(text.unicodeScalars)

        func isDigit(_ index: Int) -> Bool {
            index < scalars.count && scalars[index].value >= 48 && scalars[index].value <= 57
        }

        func takeInt(_ count: Int, from index: inout Int) -> Int? {
            guard index + count <= scalars.count else { return nil }
            var value = 0
            for offset in 0..<count {
                guard isDigit(index + offset) else { return nil }
                value = value * 10 + Int(scalars[index + offset].value - 48)
            }
            index += count
            return value
        }

        var index = 0
        guard let year = takeInt(4, from: &index), index < scalars.count, scalars[index] == "-" else { return nil }
        index += 1
        guard let month = takeInt(2, from: &index), index < scalars.count, scalars[index] == "-" else { return nil }
        index += 1
        guard let day = takeInt(2, from: &index) else { return nil }

        var hour = 0, minute = 0, second = 0
        var fraction: Double = 0
        var offsetSeconds: Int?

        if index < scalars.count, scalars[index] == "T" || scalars[index] == "t" || scalars[index] == " " {
            index += 1
            guard let h = takeInt(2, from: &index), index < scalars.count, scalars[index] == ":" else { return nil }
            index += 1
            guard let m = takeInt(2, from: &index) else { return nil }
            hour = h
            minute = m
            if index < scalars.count, scalars[index] == ":" {
                index += 1
                guard let s = takeInt(2, from: &index) else { return nil }
                second = s
            }
            if index < scalars.count, scalars[index] == "." || scalars[index] == "," {
                index += 1
                var digits = ""
                while isDigit(index) {
                    digits.unicodeScalars.append(scalars[index])
                    index += 1
                }
                fraction = Double("0." + digits) ?? 0
            }
            // Optional whitespace before the offset (YAML allows `2026-09-13 23:20:17 +02:00`).
            while index < scalars.count, scalars[index] == " " { index += 1 }
            if index < scalars.count {
                let marker = scalars[index]
                if marker == "Z" || marker == "z" {
                    offsetSeconds = 0
                    index += 1
                } else if marker == "+" || marker == "-" {
                    let sign = marker == "-" ? -1 : 1
                    index += 1
                    guard let oh = takeInt(2, from: &index) else { return nil }
                    var om = 0
                    if index < scalars.count, scalars[index] == ":" { index += 1 }
                    if isDigit(index) {
                        om = takeInt(2, from: &index) ?? 0
                    }
                    offsetSeconds = sign * (oh * 3600 + om * 60)
                }
            }
        }
        guard index == scalars.count else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        let zone = offsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? defaultTimeZone
        calendar.timeZone = zone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = zone
        guard let base = calendar.date(from: components) else { return nil }
        return fraction == 0 ? base : base.addingTimeInterval(fraction)
    }
}
