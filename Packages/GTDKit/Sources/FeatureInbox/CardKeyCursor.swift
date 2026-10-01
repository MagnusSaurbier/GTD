import Foundation
import GTDModel
import DesignSystem

// The keyboard cursor of the opened action card (issue #65, the date row #77): after the text
// fields, `⌘↩` walks the card's selectable attributes row by row — contexts, time, then the
// `+ defer` · `+ due` · `+ project` row — and ends on a row of outcome buttons. Inside a row
// `Tab` / `⇧Tab` move a *semi-highlight* between the chips, `↩` toggles (or presses) the
// highlighted one. Pure and Foundation-only, so the whole walk is unit-tested on Linux;
// `InboxSession` owns the one stored cursor and the views only draw it.

/// A row the cursor can stand on, in walking order.
public enum CardKeyRow: String, Sendable, CaseIterable, Hashable {
    /// The context chips (multi-select).
    case context
    /// The time-bucket chips (single-select).
    case time
    /// `+ defer` · `+ due` · `+ project` — `↩` opens the chip's picker (#77).
    case dates
    /// The outcome buttons — only visible while the cursor stands on them.
    case outcome
}

/// The three chips of the date row, in the order the card draws them (#77).
public enum CardDateStop: String, Sendable, CaseIterable, Hashable {
    case deferDate
    case due
    /// Opens the project picker, like the outcome row's `Project`.
    case project
}

/// The five buttons of the outcome row, in the order the ticket names them.
public enum CardOutcome: String, Sendable, CaseIterable, Hashable {
    case next
    case someday
    case waiting
    case done
    /// Opens the project chip's picker (R-8: the card stays an action and names a project).
    case project

    /// The exit a button files through — `nil` for `project`, which files nothing.
    public var exit: InboxExit? {
        switch self {
        case .next: .next
        case .someday: .someday
        case .waiting: .waiting
        case .done: .done
        case .project: nil
        }
    }

    public var title: String {
        switch self {
        case .next: Copy.next
        case .someday: Copy.someday
        case .waiting: Copy.waiting
        case .done: Copy.done
        case .project: Copy.project
        }
    }

    public var symbol: String {
        switch self {
        case .next: Symbols.next
        case .someday: Symbols.someday
        case .waiting: Symbols.waiting
        case .done: Symbols.done
        case .project: Symbols.projects
        }
    }
}

/// Where the semi-highlight stands: a row, and the index of the chip or button in it.
public struct CardKeyCursor: Sendable, Equatable, Hashable {
    public var row: CardKeyRow
    public var index: Int

    public init(row: CardKeyRow, index: Int = 0) {
        self.row = row
        self.index = index
    }

    /// How many stops `row` has. The context row has as many as the vault's config names — and
    /// is skipped entirely when that is none.
    public static func count(of row: CardKeyRow, contextCount: Int) -> Int {
        switch row {
        case .context: contextCount
        case .time: TimeBucket.allCases.count
        case .dates: CardDateStop.allCases.count
        case .outcome: CardOutcome.allCases.count
        }
    }

    /// The first non-empty row at or after `row`, on its first stop.
    public static func start(at row: CardKeyRow, contextCount: Int) -> CardKeyCursor {
        let rows = CardKeyRow.allCases
        let from = rows.firstIndex(of: row) ?? 0
        let found = rows[from...].first { count(of: $0, contextCount: contextCount) > 0 }
        return CardKeyCursor(row: found ?? .outcome)
    }

    /// Where `⌘↩` past the last text field lands: the first selectable attribute.
    public static func first(contextCount: Int) -> CardKeyCursor {
        start(at: .context, contextCount: contextCount)
    }

    /// `⌘↩` — the next row, on its first stop. The outcome row is the last one; `⌘↩` there
    /// stays put (`↩` presses the button).
    public func advanced(contextCount: Int) -> CardKeyCursor {
        let rows = CardKeyRow.allCases
        guard let here = rows.firstIndex(of: row), here + 1 < rows.count else { return self }
        return Self.start(at: rows[here + 1], contextCount: contextCount)
    }

    /// `Tab` (`+1`) / `⇧Tab` (`-1`) — the next / previous stop in the same row, wrapping round.
    public func moved(by offset: Int, contextCount: Int) -> CardKeyCursor {
        let count = Self.count(of: row, contextCount: contextCount)
        guard count > 0 else { return self }
        let wrapped = ((index + offset) % count + count) % count
        return CardKeyCursor(row: row, index: wrapped)
    }

    /// The same cursor, its index pulled back into the row — the contexts can shrink under it
    /// when the config changes on another device.
    public func clamped(contextCount: Int) -> CardKeyCursor {
        let count = Self.count(of: row, contextCount: contextCount)
        guard count > 0 else { return Self.start(at: row, contextCount: contextCount) }
        return CardKeyCursor(row: row, index: min(max(index, 0), count - 1))
    }

    /// After an outcome button was refused for missing fields: the row of the first missing
    /// **attribute**. `nil` when a text field (`Why?`/`What?`) is missing first — the card then
    /// focuses that field, as for any refusal (`ActionCardState.focusRequest`).
    public static func forMissing(_ fields: [RequiredField], contextCount: Int) -> CardKeyCursor? {
        if fields.contains(.why) || fields.contains(.what) { return nil }
        if fields.contains(.context), contextCount > 0 { return CardKeyCursor(row: .context) }
        if fields.contains(.timeEstimate) { return CardKeyCursor(row: .time) }
        return nil
    }

    /// The outcome button under the cursor, if it stands on the outcome row.
    public var outcome: CardOutcome? {
        guard row == .outcome, CardOutcome.allCases.indices.contains(index) else { return nil }
        return CardOutcome.allCases[index]
    }

    /// The date-row chip under the cursor, if it stands on the date row.
    public var dateStop: CardDateStop? {
        guard row == .dates, CardDateStop.allCases.indices.contains(index) else { return nil }
        return CardDateStop.allCases[index]
    }

    /// The time bucket under the cursor, if it stands on the time row.
    public var timeBucket: TimeBucket? {
        guard row == .time, TimeBucket.allCases.indices.contains(index) else { return nil }
        return TimeBucket.allCases[index]
    }
}
