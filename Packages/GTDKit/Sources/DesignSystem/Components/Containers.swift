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
                today: today)

            TextField(Copy.whoPlaceholder, text: $who)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .focused($isWhoFocused)
                .submitLabel(.done)
                .onSubmit { isWhoFocused = false }

            if !suggestedWho.isEmpty {
                FlowLayout {
                    ForEach(suggestedWho, id: \.self) { name in
                        Chip(name, state: who == name ? .confirmed : .suggested) { who = name }
                    }
                }
            }

            HStack {
                Spacer()
                Button(Copy.setWaiting) {
                    guard let followUp else { return }
                    let trimmedWho = who.trimmingCharacters(in: .whitespaces)
                    onSave(WaitingInfo(who: trimmedWho.isEmpty ? nil : trimmedWho, followUp: followUp))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(followUp == nil)
            }
        }
        .padding(Spacing.cardPadding)
        // A tap outside the field puts the keyboard away (no scroll view to attach
        // `.scrollDismissesKeyboard` to here).
        .contentShape(Rectangle())
        .onTapGesture { isWhoFocused = false }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Copy.done) { isWhoFocused = false }
            }
        }
        #endif
    }
}
#endif
