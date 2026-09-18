import Foundation

// STYLEGUIDE §3.6 — the drag-to-file gesture on `ItemCard`: axis lock, per-direction thresholds,
// rotation, and the fly-out offset used both by a real drag release and by `dismiss(to:)`
// (programmatic filing from a Mac key or a VoiceOver custom action). Kept Foundation-only
// (no SwiftUI) so the maths is unit-tested on Linux; `CardSwipeFiling` wraps it in a gesture.

/// The direction a card drag locks onto once past `DragThresholds.axisLock` (STYLEGUIDE §3.6).
/// Distinct from `FeatureInbox.SwipeDirection`, which additionally carries GTD filing semantics —
/// this type only describes the geometry.
public enum CardDragDirection: Sendable, Equatable, Hashable, CaseIterable {
    case left, right, up, down

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// Pure geometry for one card's drag-to-file interaction, sized to that card's frame.
/// Stateless and cheap — callers create one per gesture (or per render) from the current
/// `cardSize`.
public struct CardDragGeometry: Sendable, Equatable {
    public var cardSize: CGSize

    public init(cardSize: CGSize) {
        self.cardSize = cardSize
    }

    /// The axis/direction the drag locks onto after `DragThresholds.axisLock` pt of travel in
    /// either dimension, `nil` before that (STYLEGUIDE §3.6: "axis locks after 12 pt").
    /// Ties (equal |dx| and |dy|) resolve to horizontal.
    public func direction(for translation: CGSize) -> CardDragDirection? {
        let distance = max(abs(translation.width), abs(translation.height))
        guard distance >= DragThresholds.axisLock else { return nil }
        if abs(translation.width) >= abs(translation.height) {
            return translation.width > 0 ? .right : .left
        }
        return translation.height < 0 ? .up : .down
    }

    /// The fraction of the card's relevant dimension (width for left/right, height for up/down)
    /// this direction requires before it files (STYLEGUIDE §3.6: 35 % width, 25 % height,
    /// 40 % height for trash).
    public func threshold(for direction: CardDragDirection) -> CGFloat {
        switch direction {
        case .left, .right: DragThresholds.horizontal
        case .up: DragThresholds.vertical
        case .down: DragThresholds.trash
        }
    }

    /// How far past 0 the current translation is, as a fraction of `threshold(for:)` — 0 at the
    /// start of the drag, 1 exactly at the point the destination label/tint appear. Used to fade
    /// the label/tint in continuously rather than snapping it on. `nil` before the axis locks.
    public func progress(for translation: CGSize) -> Double {
        guard let direction = direction(for: translation) else { return 0 }
        let threshold = self.threshold(for: direction)
        guard threshold > 0 else { return 0 }
        let extent = direction.isHorizontal ? cardSize.width : cardSize.height
        guard extent > 0 else { return 0 }
        let travelled = direction.isHorizontal ? abs(translation.width) : abs(translation.height)
        return Double(travelled / extent) / Double(threshold)
    }

    /// Whether this translation has crossed its direction's filing threshold — the moment the
    /// destination label fades in, the tint overlay appears, and one `.impact(.medium)` haptic
    /// fires (STYLEGUIDE §3.6).
    public func hasCrossedThreshold(for translation: CGSize) -> Bool {
        guard direction(for: translation) != nil else { return false }
        return progress(for: translation) >= 1
    }

    /// The direction a release at this translation files to, or `nil` if the card should spring
    /// back (below threshold, or no axis locked yet).
    public func releaseDirection(for translation: CGSize) -> CardDragDirection? {
        hasCrossedThreshold(for: translation) ? direction(for: translation) : nil
    }

    /// Rotation in degrees for the live drag, signed by horizontal travel and capped at
    /// `DragThresholds.maxRotationDegrees` once the horizontal filing threshold is reached
    /// (STYLEGUIDE §3.6: "max rotation 4°"). Vertical-only drags do not rotate the card.
    public func rotation(for translation: CGSize) -> Double {
        guard cardSize.width > 0 else { return 0 }
        let horizontalThreshold = threshold(for: .right)
        guard horizontalThreshold > 0 else { return 0 }
        let fraction = Double(translation.width / cardSize.width) / Double(horizontalThreshold)
        return max(-1, min(1, fraction)) * DragThresholds.maxRotationDegrees
    }

    /// Where the card flies to when filed in `direction` — used for both a drag release past
    /// threshold and `dismiss(to:)`'s programmatic exit, so the two look identical.
    public func exitOffset(for direction: CardDragDirection) -> CGSize {
        let overshoot: CGFloat = 1.6
        switch direction {
        case .right: return CGSize(width: cardSize.width * overshoot, height: 0)
        case .left: return CGSize(width: -cardSize.width * overshoot, height: 0)
        case .up: return CGSize(width: 0, height: -cardSize.height * overshoot)
        case .down: return CGSize(width: 0, height: cardSize.height * overshoot)
        }
    }
}
