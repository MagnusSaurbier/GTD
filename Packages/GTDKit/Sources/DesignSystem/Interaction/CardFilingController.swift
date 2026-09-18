#if canImport(SwiftUI)
import SwiftUI
import Observation

/// Drives one `ItemCard`'s drag-to-file interaction (STYLEGUIDE §3.6): the live offset/rotation
/// for `cardSwipeFiling`'s gesture, the destination for the label/tint overlay, and
/// `dismiss(to:)` — the same fly-out animation triggered by a Mac key or a VoiceOver custom
/// action instead of a touch drag. One controller per card; the caller creates a fresh one (or
/// calls `reset()`) when the next card takes its place.
@MainActor
@Observable
public final class CardFilingController {
    /// The card's own size, set once its frame is known (e.g. from a `GeometryReader` or
    /// `onGeometryChange`). Drag maths is a no-op until this is non-zero.
    public var cardSize: CGSize
    public private(set) var translation: CGSize = .zero
    /// True while a drag or a programmatic `dismiss(to:)` is animating the card out — callers use
    /// this to disable the gesture and any competing input until the next card is ready.
    public private(set) var isExiting = false

    /// Bumped once each time a live drag newly crosses its direction's threshold, so a view can
    /// attach `.sensoryFeedback(.impact(weight: .medium), trigger:)` to it for the one haptic
    /// STYLEGUIDE §3.6 asks for — it does not repeat while the finger stays past the threshold.
    public private(set) var thresholdCrossingTick = 0
    private var wasPastThreshold = false

    private var geometry: CardDragGeometry { CardDragGeometry(cardSize: cardSize) }

    public init(cardSize: CGSize = .zero) {
        self.cardSize = cardSize
    }

    /// The direction the destination label/tint overlay should show, once the axis has locked.
    public var previewDirection: CardDragDirection? { geometry.direction(for: translation) }
    /// Continuous 0...1(+) fade for the destination label/tint, reaching 1 at the threshold.
    public var previewProgress: Double { geometry.progress(for: translation) }
    public var isPastThreshold: Bool { geometry.hasCrossedThreshold(for: translation) }

    func updateDrag(_ translation: CGSize) {
        guard !isExiting else { return }
        self.translation = translation
        let pastThreshold = geometry.hasCrossedThreshold(for: translation)
        if pastThreshold, !wasPastThreshold {
            thresholdCrossingTick += 1
        }
        wasPastThreshold = pastThreshold
    }

    /// Called when a drag ends: files if past threshold, otherwise springs back. Returns the
    /// direction filed to, or `nil` when the card returned to center.
    @discardableResult
    func endDrag(reduceMotion: Bool, onFile: @escaping (CardDragDirection) -> Void) -> CardDragDirection? {
        guard !isExiting else { return nil }
        wasPastThreshold = false
        guard let direction = geometry.releaseDirection(for: translation) else {
            withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) { translation = .zero }
            return nil
        }
        file(to: direction, reduceMotion: reduceMotion, onFile: onFile)
        return direction
    }

    /// Programmatic exit for keyboard filing (Mac arrow/letter keys, §4.5) or a VoiceOver custom
    /// action: animates the card out exactly as a drag release past threshold would, without a
    /// gesture ever running.
    public func dismiss(
        to direction: CardDragDirection,
        reduceMotion: Bool = false,
        onFile: @escaping (CardDragDirection) -> Void
    ) {
        file(to: direction, reduceMotion: reduceMotion, onFile: onFile)
    }

    private func file(
        to direction: CardDragDirection, reduceMotion: Bool, onFile: @escaping (CardDragDirection) -> Void
    ) {
        isExiting = true
        withAnimation(reduceMotion ? Motion.reduced : Motion.cardExit) {
            translation = geometry.exitOffset(for: direction)
        }
        onFile(direction)
    }

    /// Resets for reuse with a new card (e.g. after the exit animation finishes and the deck
    /// advances). Reusing one controller avoids a state hop when the next card mounts.
    public func reset(cardSize: CGSize? = nil) {
        if let cardSize { self.cardSize = cardSize }
        translation = .zero
        isExiting = false
        wasPastThreshold = false
        thresholdCrossingTick = 0
    }
}
#endif
