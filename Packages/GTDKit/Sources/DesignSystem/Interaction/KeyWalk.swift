import Foundation

// The keyboard walk (#65, widened to the whole inbox flow by #77): a *semi-highlight* stands on
// one stop of one row; `Tab` / `⇧Tab` move it inside the row (wrapping), `↩` presses the stop,
// `⌘↩` goes on to the next non-empty row. Pure and Foundation-only, so every screen's walk is
// unit-tested on Linux; a screen describes itself as the number of stops per row and keeps the
// meaning of each stop to itself.

/// Where the semi-highlight stands: a row and the index of the stop in it.
public struct KeyWalk: Sendable, Equatable, Hashable {
    public var row: Int
    public var index: Int

    public init(row: Int = 0, index: Int = 0) {
        self.row = row
        self.index = index
    }

    /// Whether this platform walks at all — the Mac does; the iPhone has no walk and draws no
    /// highlight.
    public static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Where a screen whose walk is on from the start begins: the first stop on the Mac,
    /// nothing elsewhere.
    public static var initial: KeyWalk? { isAvailable ? KeyWalk() : nil }

    /// The first stop of the first non-empty row — where a screen's walk starts. `nil` when the
    /// screen has nothing to walk.
    public static func first(in rows: [Int]) -> KeyWalk? {
        rows.firstIndex { $0 > 0 }.map { KeyWalk(row: $0) }
    }

    /// The same stop pulled back into the rows as they are now — a list can shrink under the
    /// highlight (a search narrowed it, a folder collapsed). A row that emptied hands over to
    /// the next non-empty row, else the previous one; `nil` when everything is empty.
    public func clamped(in rows: [Int]) -> KeyWalk? {
        guard rows.contains(where: { $0 > 0 }) else { return nil }
        let row = min(max(self.row, 0), rows.count - 1)
        if rows[row] > 0 {
            return KeyWalk(row: row, index: min(max(index, 0), rows[row] - 1))
        }
        if let later = rows.indices.first(where: { $0 > row && rows[$0] > 0 }) {
            return KeyWalk(row: later)
        }
        let earlier = rows.indices.last { $0 < row && rows[$0] > 0 }!
        return KeyWalk(row: earlier, index: rows[earlier] - 1)
    }

    /// `Tab` (`+1`) / `⇧Tab` (`-1`): the next / previous stop in the row, wrapping round.
    public func moved(by offset: Int, in rows: [Int]) -> KeyWalk {
        guard let here = clamped(in: rows) else { return self }
        let count = rows[here.row]
        return KeyWalk(row: here.row, index: ((here.index + offset) % count + count) % count)
    }

    /// `⌘↩`: the first stop of the next non-empty row. The last row keeps the highlight.
    public func advanced(in rows: [Int]) -> KeyWalk {
        guard let here = clamped(in: rows) else { return self }
        guard let next = rows.indices.first(where: { $0 > here.row && rows[$0] > 0 })
        else { return here }
        return KeyWalk(row: next)
    }

    /// The highlighted index in `row`, or `nil` when the highlight stands elsewhere.
    public func highlight(inRow row: Int) -> Int? {
        self.row == row ? index : nil
    }

    /// The stop the highlight stands on, for a screen that lists its stops row by row.
    public func stop<Stop>(in rows: [[Stop]]) -> Stop? {
        guard let here = clamped(in: rows.map(\.count)) else { return nil }
        return rows[here.row][here.index]
    }

    /// Where the highlight stands on `stop`, if the rows hold it — a click moving it there.
    public static func position<Stop: Equatable>(of stop: Stop, in rows: [[Stop]]) -> KeyWalk? {
        for (row, stops) in rows.enumerated() {
            if let index = stops.firstIndex(of: stop) { return KeyWalk(row: row, index: index) }
        }
        return nil
    }

    /// Whether `⌘↩` would move anywhere — the legend only offers `Next row` when it would.
    public func hasNextRow(in rows: [Int]) -> Bool {
        guard let here = clamped(in: rows) else { return false }
        return rows.indices.contains { $0 > here.row && rows[$0] > 0 }
    }
}

/// The walking keys as a legend line (STYLEGUIDE §3.6): `Tab ⇧Tab Move · ↩ Choose · ⌘↩ Next row
/// · Esc Cancel`. Fixed keys only — nothing here is rebindable, so nothing is looked up.
public enum KeyWalkLegend {
    public static let moveKeys = "Tab ⇧Tab"
    public static let returnKey = "↩"
    public static let commandReturnKey = "⌘↩"
    public static let escapeKey = "Esc"

    /// The rows of the line, `(key, label)`, in reading order.
    public static func entries(
        press: String, hasNextRow: Bool, back: String?
    ) -> [(key: String, label: String)] {
        var rows: [(key: String, label: String)] = [
            (moveKeys, Copy.walkMove),
            (returnKey, press),
        ]
        if hasNextRow { rows.append((commandReturnKey, Copy.walkNextRow)) }
        if let back { rows.append((escapeKey, back)) }
        return rows
    }

    public static func string(press: String, hasNextRow: Bool, back: String?) -> String {
        entries(press: press, hasNextRow: hasNextRow, back: back)
            .map { "\($0.key) \($0.label)" }
            .joined(separator: " · ")
    }
}
