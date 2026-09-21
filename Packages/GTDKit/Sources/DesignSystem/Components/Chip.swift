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
    private let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// `signal` tints a **confirmed** chip with a §2.1 signal colour (same formula as `Badge`:
    /// colour @ 18 % / 28 %, ink label, tinted symbol) — e.g. a follow-up date that has passed.
    /// The shape still carries the state (filled = confirmed); the hue only adds the signal, and
    /// `nil` / `.neutral` / any other state draws the plain chip.
    public init(
        _ title: String,
        state: ChipState,
        symbol: String? = nil,
        signal: SignalStep? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.state = state
        self.leadingSymbol = symbol
        self.signal = signal
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
            Color.ink
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

    public init(contexts: [String], selection: Binding<[String]>, disabled: Set<String> = []) {
        self.contexts = contexts
        self._selection = selection
        self.disabled = disabled
    }

    public var body: some View {
        FlowLayout {
            ForEach(contexts, id: \.self) { context in
                Chip(context, state: state(for: context)) { toggle(context) }
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

    public init(selection: Binding<TimeBucket?>) {
        self._selection = selection
    }

    public var body: some View {
        FlowLayout {
            ForEach(TimeBucket.allCases, id: \.self) { bucket in
                Chip(Copy.timeBucket(bucket), state: selection == bucket ? .confirmed : .unset) {
                    selection = selection == bucket ? nil : bucket
                }
            }
        }
    }
}

/// A date chip: `plus` symbol + `Defer` when unset, the formatted date when confirmed, dashed when suggested.
/// Tapping opens a **stock graphical `DatePicker`** — popover on Mac, medium sheet on iOS.
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

    private var picker: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // The graphical `DatePicker` has no confirm control of its own and picking a day
            // does not dismiss it — without this the only way out was swiping down (T15
            // defect 4b). Swipe-down still works; this just gives it a second, discoverable
            // way out, same as every other sheet in the app.
            HStack {
                Spacer(minLength: 0)
                Button(Copy.done) { isPresented = false }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            #endif
            DatePicker(
                label,
                selection: Binding(
                    get: { (value ?? suggestion ?? today).startOfDay() ?? Date() },
                    set: { value = Day($0) }),
                displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(Spacing.l)
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
#endif
