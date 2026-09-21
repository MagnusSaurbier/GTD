#if canImport(SwiftUI)
import SwiftUI

/// STYLEGUIDE §3.6 — the reusable drag-to-file gesture for `ItemCard`. Attach with
/// `.cardSwipeFiling(controller:isEnabled:onFile:)`; read `controller.previewDirection` /
/// `.previewProgress` to draw the destination label and tint overlay, and call
/// `controller.dismiss(to:)` for Mac-key or VoiceOver filing instead of a drag.
///
/// Swipes are disabled while any text field is focused (STYLEGUIDE §3.6) — pass `isEnabled:
/// false` for that, rather than removing the modifier, so the card never jumps.
public struct CardSwipeFiling: ViewModifier {
    let controller: CardFilingController
    let isEnabled: Bool
    let onFile: (CardDragDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: CardFilingController, isEnabled: Bool, onFile: @escaping (CardDragDirection) -> Void) {
        self.controller = controller
        self.isEnabled = isEnabled
        self.onFile = onFile
    }

    public func body(content: Content) -> some View {
        content
            .offset(controller.translation)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .sensoryFeedback(.impact(weight: .medium), trigger: controller.thresholdCrossingTick)
            .gesture(drag)
    }

    private var rotation: Double {
        CardDragGeometry(cardSize: controller.cardSize).rotation(for: controller.translation)
    }

    // `isEnabled` gates the callbacks rather than detaching the gesture, so there is no
    // Optional-Gesture typing to get wrong: disabled just means the card never moves.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard isEnabled else { return }
                controller.updateDrag(value.translation)
            }
            .onEnded { _ in
                guard isEnabled else { return }
                controller.endDrag(reduceMotion: reduceMotion, onFile: onFile)
            }
    }
}

public extension View {
    /// STYLEGUIDE §3.6 drag-to-file: card follows the finger on the locked axis, rotates up to
    /// 4°, and files (fly-out) once past its direction's threshold, or springs back otherwise.
    func cardSwipeFiling(
        controller: CardFilingController,
        isEnabled: Bool = true,
        onFile: @escaping (CardDragDirection) -> Void
    ) -> some View {
        modifier(CardSwipeFiling(controller: controller, isEnabled: isEnabled, onFile: onFile))
    }

    /// The destination-label + tint overlay that fades in past the drag threshold (STYLEGUIDE
    /// §3.6): a symbol + name on the leading/trailing/top/bottom edge, and a tint wash over the
    /// card. `tint`/`label` are supplied by the caller — GTD-specific (which direction means
    /// what) is FeatureInbox's territory; this view only places and fades them.
    func cardDragOverlay(
        controller: CardFilingController,
        tint: @escaping (CardDragDirection) -> Color,
        label: @escaping (CardDragDirection) -> (symbol: String, text: String)
    ) -> some View {
        let direction = controller.previewDirection
        let opacity = min(controller.previewProgress, 1)
        return self
            .overlay {
                if let direction {
                    Radius.cardShape.fill(tint(direction)).opacity(opacity).allowsHitTesting(false)
                }
            }
            .overlay(alignment: alignment(for: direction)) {
                if let direction {
                    let content = label(direction)
                    Label(content.text, systemImage: content.symbol)
                        .font(Typo.sectionHeader)
                        .foregroundStyle(Color.ink)
                        .padding(Spacing.m)
                        .opacity(opacity)
                }
            }
    }
}

private func alignment(for direction: CardDragDirection?) -> Alignment {
    switch direction {
    case .right: .trailing
    case .left: .leading
    case .up: .top
    case .down: .bottom
    case nil: .center
    }
}
#endif
