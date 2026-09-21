#if canImport(SwiftUI)
import SwiftUI

/// A field or chip-group label with the required-field decoration of STYLEGUIDE §3.6: "every
/// missing field or chip group shows a leading `asterisk` symbol in `signalAttention` on its
/// label until it is filled. No alert, no red borders." Reusable across `Why?`/`What?`
/// (`Typo.sectionHeader`) and the `Context`/`Time` chip-group labels (`Typo.meta`) — pass the
/// font that place already uses.
///
/// Colour is never the only carrier (§1.6): VoiceOver reads the word "required", not just a
/// symbol (§8 "badges read in full words").
public struct SectionLabel: View {
    private let title: String
    private let isMissing: Bool
    private let font: Font
    private let foreground: Color

    /// - Parameters:
    ///   - font: `Typo.sectionHeader` for `Why?`/`What?`, `Typo.meta` for a chip-group label.
    ///   - foreground: the label's own colour when it is *not* missing (`Color.ink` for a
    ///     section header, `Color.textSecondary` for a chip-group label — the existing
    ///     convention this type replaces). The asterisk is always `signalAttention`, never this
    ///     colour: shape/symbol carries the state, not a recoloured label (STYLEGUIDE §1.6).
    public init(
        _ title: String,
        isMissing: Bool = false,
        font: Font = Typo.sectionHeader,
        foreground: Color = .ink
    ) {
        self.title = title
        self.isMissing = isMissing
        self.font = font
        self.foreground = foreground
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            if isMissing {
                Image(systemName: Symbols.requiredField)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.signalAttention)
            }
            Text(title)
        }
        .font(font)
        .foregroundStyle(foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMissing ? Copy.requiredFieldLabel(title) : title)
    }
}
#endif
