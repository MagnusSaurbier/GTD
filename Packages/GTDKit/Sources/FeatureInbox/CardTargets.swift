import Foundation
import GTDModel
import DesignSystem

/// The seven-plus-one places an inbox card can go (I4), defined **once** for both platforms
/// (ARCHITECTURE §6, STYLEGUIDE §3.6). Owned by T20.
public enum CardTarget: String, Sendable, CaseIterable, Hashable, Identifiable {
    case next
    case backlog
    case maybe
    case trash
    case project
    case knowledge
    case waiting
    case deferToReview

    public var id: String { rawValue }

    /// Swipe direction on iPhone; `nil` for button/menu targets.
    public var swipe: SwipeDirection? {
        switch self {
        case .next: .right
        case .backlog: .left
        case .maybe: .up
        case .trash: .down
        default: nil
        }
    }

    /// Mac key. Arrow keys mirror the swipe directions.
    public var key: String {
        switch self {
        case .next: "→"
        case .backlog: "←"
        case .maybe: "↑"
        case .trash: "↓"
        case .project: "P"
        case .knowledge: "K"
        case .waiting: "W"
        case .deferToReview: "R"
        }
    }

    /// Targets that file the card straight away; the rest open a sheet first.
    public var isDirect: Bool { swipe != nil }

    /// The status a direct target files to.
    public var status: ActionStatus? {
        switch self {
        case .next: .next
        case .backlog: .backlog
        case .maybe: .maybe
        case .trash: .trash
        default: nil
        }
    }

    /// Fixed vocabulary (STYLEGUIDE §6.2) — never a synonym, never invented at a call site.
    public var title: String {
        switch self {
        case .next: Copy.next
        case .backlog: Copy.backlog
        case .maybe: Copy.maybe
        case .trash: Copy.trash
        case .project: Copy.project
        case .knowledge: Copy.knowledge
        case .waiting: Copy.waiting
        case .deferToReview: Copy.deferToReview
        }
    }

    /// Icon map (STYLEGUIDE §7).
    public var symbol: String {
        switch self {
        case .next: Symbols.next
        case .backlog: Symbols.backlog
        case .maybe: Symbols.maybe
        case .trash: Symbols.trash
        case .project: Symbols.projects
        case .knowledge: Symbols.knowledge
        case .waiting: Symbols.waiting
        case .deferToReview: Symbols.deferToReview
        }
    }

    /// Only Next/Backlog demand a decision about the *next physical action* (STYLEGUIDE §3.6).
    public var requiresWhat: Bool { self == .next || self == .backlog }

    /// What the undo toast says after this card left: `Moved to Backlog` (STYLEGUIDE §3.8, §6.3).
    public var undoToastLabel: String {
        self == .deferToReview ? Copy.deferToReview : Copy.movedTo(title)
    }

    /// The short label under an action-bar icon and in the Mac legend: `Defer to review` does not
    /// fit a quarter of an iPhone bar, so that one target reads `Review` there.
    public var shortTitle: String {
        self == .deferToReview ? InboxCopy.reviewShort : title
    }

    /// The four labelled buttons of the iPhone action bar — the targets that have no swipe.
    public static let buttonTargets: [CardTarget] = [.project, .knowledge, .waiting, .deferToReview]

    /// What the `⋯` menu holds: the four swipe targets, so a card can be filed without a swipe
    /// (one-handed use, Switch Control). Same order as the legend.
    public static let menuTargets: [CardTarget] = directionalTargets

    /// The four directional targets, in legend order.
    public static let directionalTargets: [CardTarget] = [.backlog, .maybe, .next, .trash]

    /// Drag tint of the Trash target: `signalOverdue` at 18 % (STYLEGUIDE §3.6). The other
    /// targets use a token colour as is (`accentWash`, `fillQuiet`).
    public static let trashTintOpacity: Double = 0.18

    /// `← Backlog  ↑ Maybe  → Next  ↓ Trash    P Project · K Knowledge · W Waiting · R Review`
    /// (STYLEGUIDE §3.6, Mac legend row). Every key names its target — a bare letter explains
    /// nothing.
    public static var keyLegend: String {
        let directions = directionalTargets.map { "\($0.key) \($0.title)" }.joined(separator: "  ")
        let letters = allCases.filter { !$0.isDirect }
            .map { "\($0.key) \($0.shortTitle)" }
            .joined(separator: " · ")
        return directions + "    " + letters
    }
}

/// Symbols the inbox card needs that the icon map of STYLEGUIDE §7 does not cover, because they
/// belong to a stock control rather than to a GTD concept. Kept here so no view writes a symbol
/// name (§9 checklist).
public enum InboxSymbols {
    /// The overflow menu of the iPhone action bar (`⋯`).
    public static let more = "ellipsis"
}

public enum SwipeDirection: Sendable, Equatable, CaseIterable {
    case left, right, up, down

    public var isHorizontal: Bool { self == .left || self == .right }

    /// The target this direction files to (STYLEGUIDE §3.6).
    public var target: CardTarget {
        switch self {
        case .right: .next
        case .left: .backlog
        case .up: .maybe
        case .down: .trash
        }
    }
}

/// Which target a drag resolves to, given the card size and the translation.
/// Pure so T20 can unit-test axis lock and thresholds without a UI (STYLEGUIDE §3.6).
public enum DragResolver {
    public static func direction(dx: CGFloat, dy: CGFloat) -> SwipeDirection? {
        guard max(abs(dx), abs(dy)) >= DragThresholds.axisLock else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy < 0 ? .up : .down
    }

    /// The target reached at this translation, or `nil` when the card springs back.
    public static func target(dx: CGFloat, dy: CGFloat, cardSize: CGSize) -> CardTarget? {
        guard let direction = direction(dx: dx, dy: dy) else { return nil }
        guard progress(dx: dx, dy: dy, cardSize: cardSize) >= threshold(for: direction) else {
            return nil
        }
        return direction.target
    }

    /// How far the drag has come towards filing, as a fraction of the threshold (0…1+).
    /// The destination label and the tint appear at `1` (STYLEGUIDE §3.6).
    public static func commitment(dx: CGFloat, dy: CGFloat, cardSize: CGSize) -> CGFloat {
        guard let direction = direction(dx: dx, dy: dy) else { return 0 }
        return progress(dx: dx, dy: dy, cardSize: cardSize) / threshold(for: direction)
    }

    /// The translation the card is allowed to follow: the dominant axis only (axis lock).
    public static func lockedTranslation(dx: CGFloat, dy: CGFloat) -> CGSize {
        guard let direction = direction(dx: dx, dy: dy) else { return CGSize(width: dx, height: dy) }
        return direction.isHorizontal ? CGSize(width: dx, height: 0) : CGSize(width: 0, height: dy)
    }

    private static func progress(dx: CGFloat, dy: CGFloat, cardSize: CGSize) -> CGFloat {
        guard let direction = direction(dx: dx, dy: dy) else { return 0 }
        return direction.isHorizontal
            ? abs(dx) / max(cardSize.width, 1)
            : abs(dy) / max(cardSize.height, 1)
    }

    private static func threshold(for direction: SwipeDirection) -> CGFloat {
        switch direction {
        case .left, .right: DragThresholds.horizontal
        case .up: DragThresholds.vertical
        case .down: DragThresholds.trash
        }
    }
}

// MARK: - Keyboard (STYLEGUIDE §3.6, Mac)

/// What a key press means on the inbox card. Resolved by `KeyMap` so the mapping is testable
/// without SwiftUI and lives next to the swipe map it mirrors.
public enum InboxKey: Sendable, Equatable {
    case target(CardTarget)
    /// `1…8` — the n-th context of `GTDConfig.contexts`, zero-based.
    case context(index: Int)
    /// `⇧1…⇧4` — a time bucket.
    case time(TimeBucket)
    /// `⌘Z`.
    case undo
    /// `Esc`.
    case quit
}

/// The single place that knows the Mac key map (ARCHITECTURE §6).
///
/// Keys only apply **when no text field is focused** — the caller checks that, because focus is
/// a view concern.
public enum KeyMap {

    /// Arrow keys mirror the swipe directions.
    public static func target(for direction: SwipeDirection) -> CardTarget { direction.target }

    /// Resolves a character press. `shift` may be reported either through the modifier flag or
    /// through the shifted character itself (`!@#$`), depending on the keyboard layout — both work.
    public static func resolve(
        _ character: Character,
        shift: Bool = false,
        command: Bool = false
    ) -> InboxKey? {
        if character == "\u{1B}" { return .quit }
        if command {
            return character.lowercased() == "z" ? .undo : nil
        }
        if let bucket = shiftedTimeBucket(character) { return .time(bucket) }
        if let digit = character.wholeNumberValue, (1...8).contains(digit) {
            if shift {
                guard digit <= TimeBucket.allCases.count else { return nil }
                return .time(TimeBucket.allCases[digit - 1])
            }
            return .context(index: digit - 1)
        }
        let letter = String(character).uppercased()
        if let target = CardTarget.allCases.first(where: { !$0.isDirect && $0.key == letter }) {
            return .target(target)
        }
        return nil
    }

    /// `⇧1…⇧4` on a US layout arrives as `!`, `@`, `#`, `$`.
    private static func shiftedTimeBucket(_ character: Character) -> TimeBucket? {
        guard let index = "!@#$".firstIndex(of: character) else { return nil }
        let offset = "!@#$".distance(from: "!@#$".startIndex, to: index)
        guard offset < TimeBucket.allCases.count else { return nil }
        return TimeBucket.allCases[offset]
    }
}
