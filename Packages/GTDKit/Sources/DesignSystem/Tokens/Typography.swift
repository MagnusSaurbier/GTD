#if canImport(SwiftUI)
import SwiftUI

/// STYLEGUIDE §2.3 — system text styles only, never `.system(size:)`.
/// Every number that can change uses `.monospacedDigit()`.
public enum Typo {
    #if os(macOS)
    public static let screenTitle: Font = .title2.weight(.semibold)
    public static let chip: Font = .callout
    #else
    public static let screenTitle: Font = .largeTitle
    public static let chip: Font = .subheadline.weight(.medium)
    #endif

    /// Raw captured text on the inbox card, routine step title.
    public static let cardText: Font = .title3
    /// `Why?`, `What?`, list section headers, wizard step titles.
    public static let sectionHeader: Font = .headline
    /// Row titles, editor text, field content.
    public static let body: Font = .body
    /// Row second line, helper text. Pair with `Color.textSecondary`.
    public static let meta: Font = .subheadline
    public static let badge: Font = Font.caption.weight(.medium).monospacedDigit()
    /// "3 of 14 left", sidebar counts, stats. Pair with `Color.textSecondary`.
    public static let counter: Font = Font.footnote.monospacedDigit()
    /// Review stat tiles.
    public static let stat: Font = Font.title.weight(.semibold).monospacedDigit()
}

/// STYLEGUIDE §5 — the only curves in the app.
public enum Motion {
    public static let standard: Animation = .snappy(duration: MotionTiming.standard)
    public static let cardExit: Animation = .easeIn(duration: MotionTiming.cardExit)
    public static let cardReturn: Animation = .spring(
        response: MotionTiming.cardReturnResponse,
        dampingFraction: MotionTiming.cardReturnDamping)
    /// What Reduce Motion replaces movement with.
    public static let reduced: Animation = .easeInOut(duration: MotionTiming.reducedCrossfade)

    /// `standard`, or the cross-fade when Reduce Motion is on.
    public static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : standard
    }
}

public extension Radius {
    /// Chips and badges (STYLEGUIDE §2.4).
    static var chipShape: Capsule { Capsule() }
    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: card, style: .continuous) }
    static var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: tile, style: .continuous) }
}

/// The one shadow in the app (STYLEGUIDE §2.4): a soft shadow in light mode, a hairline in dark.
public struct CardElevation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .shadow(
                color: colorScheme == .dark
                    ? .clear
                    : .black.opacity(Elevation.cardShadowOpacity),
                radius: Elevation.cardShadowRadius,
                y: Elevation.cardShadowY)
            .overlay {
                if colorScheme == .dark {
                    Radius.cardShape.stroke(Color.hairline, lineWidth: Elevation.hairlineWidth)
                }
            }
    }
}

public extension View {
    func cardElevation() -> some View { modifier(CardElevation()) }
}
#endif
