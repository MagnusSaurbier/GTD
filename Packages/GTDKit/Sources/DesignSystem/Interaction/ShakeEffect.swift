#if canImport(SwiftUI)
import SwiftUI

/// STYLEGUIDE §3.6 validation shake, driven as one continuous `GeometryEffect` so the whole
/// 6 pt / 0.3 s motion is a single `withAnimation` rather than a chain of timers.
private struct ShakeGeometry: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = ShakeMetrics.amplitude * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// Shakes the content once (6 pt, 0.3 s) whenever `trigger` changes (STYLEGUIDE §3.6: "the card
/// shakes once"). Under Reduce Motion it does nothing at all (§5: "no rotation, no shake — use
/// focus + haptic only"); pair it with moving focus to the first missing field and an
/// `.error` `.sensoryFeedback`, never with the shake alone.
private struct ShakeEffect: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeGeometry(animatableData: phase))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.linear(duration: ShakeMetrics.duration)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// See `ShakeEffect`. `trigger` is any value that changes once per failed validation attempt
    /// (an attempt counter works well — the shake fires on *change*, not on a particular value).
    func shake(trigger: Int) -> some View {
        modifier(ShakeEffect(trigger: trigger))
    }
}
#endif
