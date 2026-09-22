import Foundation

// Platform-free half of the token set (STYLEGUIDE §2.4, §5). Colours, fonts, shapes and
// animations need SwiftUI and live in `Colors.swift` / `Typography.swift` / `Motion.swift`.

/// 4-pt grid (STYLEGUIDE §2.4). Feature code never writes a literal padding.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32

    /// Horizontal page inset: 16 on iPhone, 20 in Mac content.
    #if os(macOS)
    public static let screenMargin: CGFloat = 20
    #else
    public static let screenMargin: CGFloat = 16
    #endif

    /// Inside inbox and routine cards.
    public static let cardPadding: CGFloat = 20
    /// Between chips, both axes.
    public static let chipGap: CGFloat = 8
    /// Row top/bottom padding.
    public static let rowVertical: CGFloat = 10

    /// Minimum hit target (STYLEGUIDE §2.4).
    #if os(macOS)
    public static let minHitTarget: CGFloat = 24
    public static let chipHeight: CGFloat = 24
    #else
    public static let minHitTarget: CGFloat = 44
    public static let chipHeight: CGFloat = 34
    #endif

    /// Max width of a card on wide layouts.
    public static let cardMaxWidth: CGFloat = 560
}

/// Size of a Mac sheet whose content scrolls (a grouped `Form` or a `List`). Such content has no
/// intrinsic height, so the sheet needs an ideal size to open at and a minimum to stay usable;
/// never a fixed height, which is what clips long pickers. iOS sizes sheets by detent instead.
public enum SheetMetrics {
    public static let minWidth: CGFloat = 380
    public static let idealWidth: CGFloat = 440
    public static let minHeight: CGFloat = 320
    public static let idealHeight: CGFloat = 520
    /// Tallest an inline run of rows may grow inside a content-sized sheet before it scrolls
    /// (`OverflowScroll`).
    public static let inlineRowsMaxHeight: CGFloat = 280
    /// Tallest the opened action card may stand inside a content-sized Mac sheet before it
    /// scrolls (`MacCardScroll`): a long note's body must not push the sheet's buttons and
    /// legend off the window. The cap is also bounded by the presenting window
    /// (`cardCap(forWindowHeight:)`) — a sheet is allowed to hang below its window, and did.
    public static let cardMaxHeight: CGFloat = 520
    /// Shortest the card is ever capped to, so a small window still shows a few lines.
    public static let cardMinHeight: CGFloat = 240
    /// What the card's Mac sheet needs besides the card: counter, action bar, legend, toast
    /// slot, the `Undo`/`Close` row and the spacing between them.
    public static let cardSheetChrome: CGFloat = 240

    /// The card cap for a sheet on a window of this content height; `nil` (unknown yet) gives
    /// the plain `cardMaxHeight`.
    public static func cardCap(forWindowHeight height: CGFloat?) -> CGFloat {
        guard let height else { return cardMaxHeight }
        return max(cardMinHeight, min(cardMaxHeight, height - cardSheetChrome))
    }
}

/// Corner radii. `Radius.chipShape` (a `Capsule`) lives in the SwiftUI half.
public enum Radius {
    public static let card: CGFloat = 24
    public static let tile: CGFloat = 12
    /// Heatmap cells.
    public static let cell: CGFloat = 4
}

/// The one shadow in the app (STYLEGUIDE §2.4). Dark mode uses a hairline stroke instead.
public enum Elevation {
    public static let cardShadowOpacity: Double = 0.10
    public static let cardShadowRadius: CGFloat = 16
    public static let cardShadowY: CGFloat = 6
    public static let hairlineWidth: CGFloat = 0.5
}

/// Durations behind `Motion` (STYLEGUIDE §5). No other curves exist.
public enum MotionTiming {
    public static let standard: Double = 0.3
    public static let cardExit: Double = 0.25
    public static let cardReturnResponse: Double = 0.35
    public static let cardReturnDamping: Double = 0.8
    /// Reduce Motion replaces movement with a cross-fade of this length.
    public static let reducedCrossfade: Double = 0.2
    /// Check-draw on completing an action, then the row collapses.
    public static let checkDraw: Double = 0.25
    public static let rowCollapse: Double = 0.4
    /// Undo toast auto-dismiss.
    public static let toastDuration: Double = 5
    /// A sheet's own presentation animation before content inside it is safe to focus
    /// programmatically — focusing while the sheet is still animating in produces a stuck/ghost
    /// keyboard accessory view (iOS). Anything that auto-focuses a field on a freshly presented
    /// sheet waits this long first.
    public static let sheetSettle: Double = 0.45
}

/// Validation shake (STYLEGUIDE §3.6, §5): "shakes once (6 pt, 0.3 s)". Reduce Motion drops the
/// shake entirely — focus + the `.error` haptic still carry the signal (§5: "no shake").
public enum ShakeMetrics {
    public static let amplitude: CGFloat = 6
    public static let duration: Double = 0.3
}

/// Inbox-card drag behaviour (STYLEGUIDE §3.6). Pure numbers so the gesture logic is testable.
public enum DragThresholds {
    /// The drag locks onto one axis after this distance.
    public static let axisLock: CGFloat = 12
    /// Fraction of the card width that files horizontally.
    public static let horizontal: CGFloat = 0.35
    /// Fraction of the card height that files upward.
    public static let vertical: CGFloat = 0.25
    /// Trash needs a longer pull.
    public static let trash: CGFloat = 0.40
    public static let maxRotationDegrees: Double = 4
}
