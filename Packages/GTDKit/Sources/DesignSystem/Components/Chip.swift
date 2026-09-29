#if canImport(SwiftUI)
import SwiftUI
import GTDModel

/// The main input control (STYLEGUIDE §3.1). One component, four states — variation comes from
/// state, never from a new component.
///
/// Tap: `unset` → `confirmed`, `suggested` → `confirmed`, `confirmed` → `unset`.
/// A `suggested` chip is a proposal and is **not** written to the file until confirmed.
public struct Chip: View {
    private let title: String
    private let state: ChipState
    private let leadingSymbol: String?
    private let signal: SignalStep?
    private let isKeyHighlighted: Bool
    private let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// `signal` tints a **confirmed** chip with a §2.1 signal colour (same formula as `Badge`:
    /// colour @ 18 % / 28 %, ink label, tinted symbol) — e.g. a follow-up date that has passed.
    /// The shape still carries the state (filled = confirmed); the hue only adds the signal, and
    /// `nil` / `.neutral` / any other state draws the plain chip.
    ///
    /// `isKeyHighlighted` is the keyboard's *semi-highlight* (Mac inbox walk, #65): a ring around
    /// the chip that keeps its own fill, so it reads as neither unset nor confirmed, plus a
    /// preview of what `↩` will do — an unset chip takes a faint wash of the confirmed fill, a
    /// confirmed chip loses some of its fill.
    public init(
        _ title: String,
        state: ChipState,
        symbol: String? = nil,
        signal: SignalStep? = nil,
        isKeyHighlighted: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.state = state
        self.leadingSymbol = symbol
        self.signal = signal
        self.isKeyHighlighted = isKeyHighlighted
        self.action = action
    }

    public var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let symbol = effectiveSymbol {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(signalTint ?? foreground)
                }
                Text(title)
            }
            .font(Typo.chip)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: Spacing.chipHeight)
            .background(background)
            .overlay { outline }
            .clipShape(Radius.chipShape)
            .contentShape(Radius.chipShape)
        }
        .buttonStyle(.plain)
        .keyHighlight(isKeyHighlighted, in: Radius.chipShape)
        .disabled(state == .disabled)
        .sensoryFeedback(.selection, trigger: state)
        .accessibilityAddTraits(state == .confirmed ? [.isSelected] : [])
        .accessibilityValue(accessibilityValue)
    }

    private var effectiveSymbol: String? {
        state == .suggested ? Symbols.suggestion : leadingSymbol
    }

    #if os(macOS)
    private var horizontalPadding: CGFloat { 10 }
    #else
    private var horizontalPadding: CGFloat { 12 }
    #endif

    /// The signal colour, only for a confirmed chip carrying a non-neutral signal.
    private var signalTint: Color? {
        guard state == .confirmed, let signal, signal != .neutral else { return nil }
        return .signal(Badge.style(signal))
    }

    private var foreground: Color {
        switch state {
        case .unset, .suggested: .textSecondary
        case .confirmed: signalTint == nil ? .inkInverse : .ink
        case .disabled: .textTertiary
        }
    }

    @ViewBuilder private var background: some View {
        if let signalTint {
            signalTint.opacity(colorScheme == .dark ? 0.28 : 0.18)
        } else if state == .confirmed {
            // Highlighted: `↩` would clear it — the fill already gives way a little.
            Color.ink.opacity(isKeyHighlighted ? 0.72 : 1)
        } else if isKeyHighlighted, state != .disabled {
            // Highlighted: `↩` would confirm it — a faint wash of the fill it would take.
            Color.ink.opacity(0.12)
        } else {
            Color.clear
        }
    }

    /// STYLEGUIDE §8: outline thickens to 1.5 pt under `accessibilityContrast == .increased`.
    private var outlineWidth: CGFloat { contrast == .increased ? 1.5 : 1 }

    @ViewBuilder private var outline: some View {
        switch state {
        case .suggested:
            Radius.chipShape.strokeBorder(
                Color.textSecondary,
                style: StrokeStyle(lineWidth: outlineWidth, dash: [4, 3]))
        case .unset, .disabled:
            Radius.chipShape.strokeBorder(Color.hairline, lineWidth: outlineWidth)
        case .confirmed:
            EmptyView()
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .unset: "unset"
        case .suggested: "suggested"
        case .confirmed: "confirmed"
        case .disabled: "unavailable"
        }
    }
}

/// The keyboard's semi-highlight (#65): a 2 pt `ink` ring **outside** the control's own shape,
/// so whatever the control draws inside (a chip's fill or none, a bordered button) stays
/// readable. It springs in slightly larger than its final size; Reduce Motion drops the spring.
public struct KeyHighlightRing<S: InsettableShape>: ViewModifier {
    let isOn: Bool
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlay {
                // Drawn in a frame 4 pt larger on every side rather than with `inset(by: -3)`:
                // a negatively inset `Capsule` keeps its old corner radius and grows flat ends.
                shape.strokeBorder(Color.ink, lineWidth: 2)
                    .padding(-4)
                    .scaleEffect(isOn || reduceMotion ? 1 : 1.08)
                    .opacity(isOn ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? Motion.reduced : Motion.standard, value: isOn)
            .accessibilityHint(isOn ? Copy.keyHighlightHint : "")
    }
}

public extension View {
    /// See `KeyHighlightRing`.
    func keyHighlight<S: InsettableShape>(_ isOn: Bool, in shape: S) -> some View {
        modifier(KeyHighlightRing(isOn: isOn, shape: shape))
    }
}

/// Wraps chips onto as many lines as they need, with `Spacing.chipGap` on both axes
/// (STYLEGUIDE §3.1 — never a horizontal scroller on the card).
public struct FlowLayout: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = Spacing.chipGap) {
        self.spacing = spacing
    }

    // The row-wrapping maths itself lives in `FlowLayoutEngine` (Foundation-only, unit-tested on
    // Linux); this type is the thin SwiftUI `Layout` witness over it.

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return FlowLayoutEngine.layout(sizes: sizes, maxWidth: maxWidth, spacing: spacing).size
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: bounds.width, spacing: spacing)
        for placement in result.placements {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.position.x, y: bounds.minY + placement.position.y),
                proposal: ProposedViewSize(sizes[placement.index]))
        }
    }
}

// MARK: - Thin group helpers

/// Multi-select context chips (A4). No group ever has a default selection.
public struct ContextChipGroup: View {
    private let contexts: [String]
    @Binding private var selection: [String]
    private let disabled: Set<String>
    private let highlighted: Int?

    /// `highlighted` — the index of the chip carrying the keyboard's semi-highlight, if any.
    public init(
        contexts: [String], selection: Binding<[String]>, disabled: Set<String> = [],
        highlighted: Int? = nil
    ) {
        self.contexts = contexts
        self._selection = selection
        self.disabled = disabled
        self.highlighted = highlighted
    }

    public var body: some View {
        FlowLayout {
            ForEach(Array(contexts.enumerated()), id: \.element) { index, context in
                Chip(context, state: state(for: context), isKeyHighlighted: highlighted == index) {
                    toggle(context)
                }
            }
        }
    }

    private func state(for context: String) -> ChipState {
        if disabled.contains(context) { return .disabled }
        return selection.contains(context) ? .confirmed : .unset
    }

    private func toggle(_ context: String) {
        if let index = selection.firstIndex(of: context) {
            selection.remove(at: index)
        } else {
            selection.append(context)
        }
    }
}

/// Single-select time-bucket chips (I3). `nil` stays a legal, visible state.
public struct TimeBucketChipGroup: View {
    @Binding private var selection: TimeBucket?
    private let highlighted: Int?

    /// `highlighted` — the index (in `TimeBucket.allCases`) of the chip carrying the keyboard's
    /// semi-highlight, if any.
    public init(selection: Binding<TimeBucket?>, highlighted: Int? = nil) {
        self._selection = selection
        self.highlighted = highlighted
    }

    public var body: some View {
        FlowLayout {
            ForEach(Array(TimeBucket.allCases.enumerated()), id: \.element) { index, bucket in
                Chip(
                    Copy.timeBucket(bucket),
                    state: selection == bucket ? .confirmed : .unset,
                    isKeyHighlighted: highlighted == index
                ) {
                    selection = selection == bucket ? nil : bucket
                }
            }
        }
    }
}

/// A date chip: `plus` symbol + `Defer` when unset, the formatted date when confirmed, dashed when suggested.
/// Tapping opens the app's own `DayPicker` — popover on Mac, medium sheet on iOS. One click
/// on a day sets the date and closes the picker.
public struct DateValueChip: View {
    private let label: String
    @Binding private var value: Day?
    private let suggestion: Day?
    private let today: Day
    private let signal: SignalStep?
    private let signalSymbol: String?

    @State private var isPresented = false

    /// `signal` (+ optional `signalSymbol`) tints the confirmed date — see `Chip.init`. The caller
    /// takes the step from `Rules.signals`; this component never decides that a date is late.
    public init(
        label: String,
        value: Binding<Day?>,
        suggestion: Day? = nil,
        today: Day = Day.today(),
        signal: SignalStep? = nil,
        signalSymbol: String? = nil
    ) {
        self.label = label
        self._value = value
        self.suggestion = suggestion
        self.today = today
        self.signal = signal
        self.signalSymbol = signalSymbol
    }

    public var body: some View {
        Chip(title, state: state, symbol: symbol, signal: signal) {
            // STYLEGUIDE §3.1: suggested → confirmed on tap (the +7 d follow-up etc. is never
            // silently written); a **second** tap, once it is `.confirmed`, opens the picker to
            // change it. Only `.unset`/`.confirmed` open the picker directly.
            if state == .suggested, let suggestion {
                value = suggestion
            } else {
                isPresented = true
            }
        }
        .popover(isPresented: $isPresented) { picker }
    }

    private var symbol: String? {
        if value == nil && suggestion == nil { return Symbols.addValue }
        return value != nil && signal != nil && signal != .neutral ? signalSymbol : nil
    }

    private var title: String {
        if let value { return DateText.short(value, today: today) }
        if let suggestion { return DateText.short(suggestion, today: today) }
        // The chip already draws the `plus` symbol — a literal "+" here doubled it (P4).
        // Lower case, never title case (STYLEGUIDE §3.1: `+ defer` / `+ due`, T15 defect 9).
        return Copy.unsetValueChipTitle(label)
    }

    private var state: ChipState {
        if value != nil { return .confirmed }
        if suggestion != nil { return .suggested }
        return .unset
    }

    /// The app's own `DayPicker`: one click on a day writes the value and closes the picker.
    /// The stock graphical `DatePicker` that used to sit here looked right but could not be
    /// used — on macOS its clicks never reached this chip's binding, so a follow-up/defer/due
    /// date simply could not be set from the calendar (user report, 2026-09-24).
    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            // The sheet's own way out for someone who opened it and changed their mind; picking
            // a day closes it too. Swipe-down still works (T15 defect 4b).
            HStack {
                Spacer(minLength: 0)
                Button(Copy.done) { isPresented = false }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            #endif
            DayPicker(selection: value, today: today) { day in
                value = day
                isPresented = false
            }
            .padding(Spacing.l)
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
#endif
