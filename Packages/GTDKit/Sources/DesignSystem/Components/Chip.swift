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
    private let action: () -> Void

    public init(
        _ title: String,
        state: ChipState,
        symbol: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.state = state
        self.leadingSymbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let symbol = effectiveSymbol {
                    Image(systemName: symbol).symbolRenderingMode(.hierarchical)
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

    private var foreground: Color {
        switch state {
        case .unset, .suggested: .textSecondary
        case .confirmed: .inkInverse
        case .disabled: .textTertiary
        }
    }

    @ViewBuilder private var background: some View {
        if state == .confirmed { Color.ink } else { Color.clear }
    }

    @ViewBuilder private var outline: some View {
        switch state {
        case .suggested:
            Radius.chipShape.strokeBorder(
                Color.textSecondary,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .unset, .disabled:
            Radius.chipShape.strokeBorder(Color.hairline, lineWidth: 1)
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

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth == .infinity ? width : maxWidth), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
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

/// A date chip: `+ defer` when unset, the formatted date when confirmed, dashed when suggested.
/// Tapping opens a **stock graphical `DatePicker`** — popover on Mac, medium sheet on iOS.
public struct DateValueChip: View {
    private let label: String
    @Binding private var value: Day?
    private let suggestion: Day?
    private let today: Day

    @State private var isPresented = false

    public init(
        label: String,
        value: Binding<Day?>,
        suggestion: Day? = nil,
        today: Day = Day.today()
    ) {
        self.label = label
        self._value = value
        self.suggestion = suggestion
        self.today = today
    }

    public var body: some View {
        Chip(title, state: state, symbol: value == nil && suggestion == nil ? "plus" : nil) {
            isPresented = true
        }
        .popover(isPresented: $isPresented) { picker }
    }

    private var title: String {
        if let value { return DateText.short(value, today: today) }
        if let suggestion { return DateText.short(suggestion, today: today) }
        return "+ \(label)"
    }

    private var state: ChipState {
        if value != nil { return .confirmed }
        if suggestion != nil { return .suggested }
        return .unset
    }

    private var picker: some View {
        DatePicker(
            label,
            selection: Binding(
                get: { (value ?? suggestion ?? today).startOfDay() ?? Date() },
                set: { value = Day($0) }),
            displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(Spacing.l)
            #if os(iOS)
            .presentationDetents([.medium])
            #endif
    }
}
#endif
