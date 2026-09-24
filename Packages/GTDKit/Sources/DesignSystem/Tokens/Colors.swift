#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// STYLEGUIDE §2.1. Base surfaces and text are system semantic colours — never redefined.
// Brand and signal colours are **code-defined** so nothing depends on the asset catalog being
// compiled (see ARCHITECTURE §5, "Platform guards"). `DesignSystem/Resources/Colors.xcassets`
// carries the same values for Xcode-side tooling and for the app target's `AccentColor`.

public extension Color {

    // MARK: Base (system semantic)

    /// Text, confirmed chip fill, checkmarks.
    static var ink: Color { .primary }
    /// Text on an ink fill.
    static var inkInverse: Color { platformBackground }
    static var textSecondary: Color { .secondary }
    /// Placeholders, disabled, counters at rest.
    static var textTertiary: Color { Color.secondary.opacity(0.55) }
    /// Page background.
    static var surface: Color { platformBackground }
    /// Behind cards (iOS), review wizard.
    static var surfaceGrouped: Color { platformGroupedBackground }
    /// Inbox/routine card, stat tiles.
    static var surfaceCard: Color { platformCardBackground }
    /// Chip outline, dividers.
    static var hairline: Color { Color.gray.opacity(0.35) }
    /// Neutral badge background, empty heatmap cell.
    static var fillQuiet: Color { Color.gray.opacity(0.18) }

    // MARK: Brand and signal

    /// The single fixed accent (slate blue). Primary button, selection, links, focus, progress.
    /// STYLEGUIDE §8: thicker outlines aside, this is the one token that also has dedicated
    /// **High Contrast** values (`#2F5A87` / `#9CC6EE`), resolved with the other three the same
    /// way light/dark are — see `dynamicContrast`.
    static var gtdAccent: Color {
        dynamicContrast(
            light: (0.247, 0.431, 0.620), dark: (0.498, 0.690, 0.871),
            lightHighContrast: (0.184, 0.353, 0.529), darkHighContrast: (0.612, 0.776, 0.933))
    }

    /// Selected-row background where system selection is not used; drag-target tint for Next.
    static var accentWash: Color { gtdAccent.opacity(0.18) }

    /// The light-blue wash a sidebar section or project row wears while a dragged note it
    /// would accept hovers over it (E3, the user's call 2026-09-24: "light up light blue").
    /// System blue rather than the accent, so it reads as "drop here" against the selected
    /// row's own highlight.
    static var dropTargetWash: Color { Color.blue.opacity(0.28) }

    /// Step 1 — aging / approaching.
    static var signalAging: Color { .yellow }
    /// Step 2 — needs attention.
    static var signalAttention: Color { .orange }
    /// Step 3 — overdue / broken.
    static var signalOverdue: Color { .red }
    /// Completion moments only. Never a resting state.
    static var signalDone: Color { .green }

    /// The colour of a semantic step (STYLEGUIDE §2.1 formula).
    static func signal(_ step: SignalStepStyle) -> Color {
        switch step {
        case .neutral: .textSecondary
        case .aging: .signalAging
        case .attention: .signalAttention
        case .overdue: .signalOverdue
        }
    }

    // MARK: Platform plumbing

    private static var platformBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.white
        #endif
    }

    private static var platformGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color.white
        #endif
    }

    private static var platformCardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.white
        #endif
    }

    /// A colour with separate light and dark values, defined in code.
    static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1)
        })
        #else
        return Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }

    /// Like `dynamic(light:dark:)`, with extra values for `accessibilityContrast == .increased`
    /// (STYLEGUIDE §8). On iOS this resolves per-trait, exactly like light/dark, so it updates
    /// live when Increase Contrast toggles. On macOS the same information is in the
    /// `NSAppearance` the provider is handed — Increase Contrast switches the app to the
    /// `accessibilityHighContrast…` appearances — so matching against all four names keeps this
    /// a pure function of its argument (T41: the earlier version read
    /// `NSWorkspace.shared` from inside the provider, which is a main-actor hop out of a
    /// nonisolated closure under Swift 6, and only tracked the setting by luck of redraw).
    static func dynamicContrast(
        light: (Double, Double, Double),
        dark: (Double, Double, Double),
        lightHighContrast: (Double, Double, Double),
        darkHighContrast: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let increased = traits.accessibilityContrast == .high
            let isDark = traits.userInterfaceStyle == .dark
            let rgb = isDark
                ? (increased ? darkHighContrast : dark)
                : (increased ? lightHighContrast : light)
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            // `NSAppearance.Name` is a RawRepresentable struct, not an enum: compare, do not switch.
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let increased = match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
            let rgb = isDark
                ? (increased ? darkHighContrast : dark)
                : (increased ? lightHighContrast : light)
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        return Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

/// Mirror of `GTDModel.SignalStep` for the colour formula, so `Color` needs no model import
/// in its own file. `Badge` maps between the two.
public enum SignalStepStyle: Sendable, Equatable, CaseIterable {
    case neutral
    case aging
    case attention
    case overdue
}
#endif
