import Foundation
import GTDModel
import DesignSystem

/// The seven-plus-one places an inbox card can go (I4), defined **once** for both platforms
/// (ARCHITECTURE §6, STYLEGUIDE §3.6). Owned by T20.
public enum CardTarget: String, Sendable, CaseIterable, Hashable {
    case next
    case backlog
    case maybe
    case trash
    case project
    case knowledge
    case waiting
    case deferToReview

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
}

public enum SwipeDirection: Sendable, Equatable, CaseIterable {
    case left, right, up, down

    public var isHorizontal: Bool { self == .left || self == .right }
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
        let progress = direction.isHorizontal
            ? abs(dx) / max(cardSize.width, 1)
            : abs(dy) / max(cardSize.height, 1)
        let threshold: CGFloat = switch direction {
        case .left, .right: DragThresholds.horizontal
        case .up: DragThresholds.vertical
        case .down: DragThresholds.trash
        }
        guard progress >= threshold else { return nil }
        return CardTarget.allCases.first { $0.swipe == direction }
    }
}
