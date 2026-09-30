#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore

/// The solid elevated card behind inbox processing and routine steps (STYLEGUIDE §3.5).
/// It does not scroll internally; it grows with its content.
public struct ItemCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            content
        }
        .frame(maxWidth: Spacing.cardMaxWidth, alignment: .leading)
        .padding(Spacing.cardPadding)
        .background(Color.surfaceCard, in: Radius.cardShape)
        .cardElevation()
    }
}

/// The floating control bar of the inbox card and the routine runner (STYLEGUIDE §2.5, §3.7):
/// `.glassEffect()` inside one `GlassEffectContainer` on iOS 26 / macOS 26, a `.ultraThinMaterial`
/// capsule everywhere else `.glassEffect()` cannot be verified to exist or Reduce Transparency
/// asks for a solid background (STYLEGUIDE §8: "glass bars fall back to `surfaceCard` + hairline").
public struct GlassActionBar<Content: View>: View {
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Group {
            if #available(iOS 26, macOS 26, *), !reduceTransparency {
                GlassEffectContainer {
                    bar.glassEffect()
                }
            } else {
                bar
                    .background(materialFallback, in: Radius.chipShape)
                    .overlay { fallbackOutline }
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
    }

    private var bar: some View {
        HStack(spacing: Spacing.m) { content }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
    }

    private var materialFallback: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.surfaceCard) : AnyShapeStyle(.ultraThinMaterial)
    }

    @ViewBuilder private var fallbackOutline: some View {
        if reduceTransparency {
            Radius.chipShape.strokeBorder(Color.hairline, lineWidth: Elevation.hairlineWidth)
        }
    }
}

/// Bottom-anchored undo toast (N6, STYLEGUIDE §3.8). One at a time; a new one replaces the old.
/// Same glass-with-fallback rule as `GlassActionBar`.
public struct UndoToast: View {
    private let label: String
    private let onUndo: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(label: String, onUndo: @escaping () -> Void) {
        self.label = label
        self.onUndo = onUndo
    }

    public var body: some View {
        Group {
            if #available(iOS 26, macOS 26, *), !reduceTransparency {
                GlassEffectContainer {
                    toast.glassEffect()
                }
            } else {
                toast
                    .background(reduceTransparency ? AnyShapeStyle(Color.surfaceCard) : AnyShapeStyle(.ultraThinMaterial), in: Radius.chipShape)
                    .overlay {
                        if reduceTransparency {
                            Radius.chipShape.strokeBorder(Color.hairline, lineWidth: Elevation.hairlineWidth)
                        }
                    }
            }
        }
    }

    private var toast: some View {
        HStack(spacing: Spacing.m) {
            Text(label).font(Typo.meta).foregroundStyle(Color.ink)
            Button(Copy.undo, action: onUndo)
                .font(Typo.meta)
                .buttonStyle(.plain)
                .foregroundStyle(Color.gtdAccent)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// W1/D39 — setting `waiting` requires the **follow-up date**; who is optional (STYLEGUIDE §3.6).
///
/// The `+7 days` default is offered as a **suggested** (dashed) chip and is not part of the
/// returned `WaitingInfo` until the user confirms it: a default must never be written silently.
/// `Set waiting` stays disabled until a date is confirmed; a blank who is sent as `nil`, never
/// an empty string, so no `waitingFor:` line is written (D39, "no lying defaults").
public struct WaitingInfoSheet: View {
    private let initial: WaitingInfo?
    private let suggestedWho: [String]
    private let today: Day
    private let onSave: (WaitingInfo) -> Void

    @State private var who: String
    @State private var followUp: Day?
    @Environment(\.dismiss) private var dismiss
    /// O3 — this sheet has no scroll view to attach `.scrollDismissesKeyboard` to, and before
    /// this the keyboard only closed via the sheet's own drag gesture, covering Cancel/save.
    /// `@FocusState` + a keyboard toolbar Done button (the `ActionDetailView` pattern) plus a
    /// tap-outside-the-field dismissal fix that.
    @FocusState private var isWhoFocused: Bool
    /// The Mac keyboard walk (#77): follow-up chip → who suggestions → `Set waiting`. It starts
    /// on the follow-up chip, a click on a chip or the button moves it there, the who field
    /// ends it and `↩` in the field hands it on to `Set waiting`.
    @State private var walk: KeyWalk? = KeyWalk.initial
    @FocusState private var hasWalkFocus: Bool
    @State private var isPickerOpen = false

    public init(
        initial: WaitingInfo? = nil,
        suggestedWho: [String] = [],
        today: Day = Day.today(),
        onSave: @escaping (WaitingInfo) -> Void
    ) {
        self.initial = initial
        self.suggestedWho = suggestedWho
        self.today = today
        self.onSave = onSave
        _who = State(initialValue: initial?.who ?? "")
        _followUp = State(initialValue: initial?.followUp)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.waiting).font(Typo.sectionHeader)

            SectionLabel(Copy.followUp, isMissing: followUp == nil, font: Typo.meta, foreground: .textSecondary)
            DateValueChip(
                label: Copy.followUp,
                value: $followUp,
                suggestion: WaitingInfo.suggestedFollowUp(from: today),
                today: today,
                isKeyHighlighted: walk?.highlight(inRow: 0) == 0,
                isPickerPresented: $isPickerOpen,
                onTap: { point(at: KeyWalk(row: 0)) })

            TextField(Copy.whoPlaceholder, text: $who)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .focused($isWhoFocused)
                .submitLabel(.done)
                .onSubmit {
                    isWhoFocused = false
                    point(at: KeyWalk(row: 2))
                }

            if !suggestedWho.isEmpty {
                FlowLayout {
                    ForEach(Array(suggestedWho.enumerated()), id: \.element) { index, name in
                        Chip(
                            name, state: who == name ? .confirmed : .suggested,
                            isKeyHighlighted: walk?.highlight(inRow: 1) == index
                        ) {
                            who = name
                            point(at: KeyWalk(row: 1, index: index))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(Copy.setWaiting) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(followUp == nil)
                    .keyHighlight(
                        walk?.highlight(inRow: 2) == 0, in: RoundedRectangle(cornerRadius: 10))
            }

            if walk != nil {
                KeyWalkLegendLine(press: Copy.walkChoose, hasNextRow: walk?.row != 2)
            }
        }
        .padding(Spacing.cardPadding)
        // Without an explicit top alignment the sheet centers this short VStack in the whole
        // `.medium` detent, leaving a large empty gap above it (T15 defect 4c).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A tap outside the field puts the keyboard away (no scroll view to attach
        // `.scrollDismissesKeyboard` to here).
        .contentShape(Rectangle())
        .onTapGesture { isWhoFocused = false }
        .keyWalkKeys(
            focus: $hasWalkFocus,
            onMove: { offset in walk = (walk ?? KeyWalk()).moved(by: offset, in: walkRows) },
            onPress: press,
            onNextRow: { walk = (walk ?? KeyWalk()).advanced(in: walkRows) })
        .onChange(of: isWhoFocused) { _, focused in
            // A click into the field ends the walk, as on the inbox card.
            if focused { walk = nil }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Copy.done) { isWhoFocused = false }
            }
        }
        #endif
    }

    /// Stops per row: the follow-up chip, the who suggestions, `Set waiting`.
    private var walkRows: [Int] { [1, suggestedWho.count, 1] }

    /// A click (or the field's `↩`) puts the highlight there and hands the keys to the walk.
    private func point(at stop: KeyWalk) {
        guard KeyWalk.isAvailable else { return }
        walk = stop.clamped(in: walkRows)
        hasWalkFocus = true
    }

    /// `↩` does what a click on the highlighted stop does.
    private func press() {
        guard let stop = walk?.clamped(in: walkRows) else {
            walk = KeyWalk.first(in: walkRows)
            return
        }
        switch stop.row {
        case 0:
            // The chip's own rule: a suggestion is confirmed first, a set date opens the picker.
            if followUp == nil {
                followUp = WaitingInfo.suggestedFollowUp(from: today)
            } else {
                isPickerOpen = true
            }
        case 1:
            who = suggestedWho[stop.index]
        default:
            save()
        }
    }

    private func save() {
        guard let followUp else { return }
        let trimmedWho = who.trimmingCharacters(in: .whitespaces)
        onSave(WaitingInfo(who: trimmedWho.isEmpty ? nil : trimmedWho, followUp: followUp))
        dismiss()
    }
}
#endif
