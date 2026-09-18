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

/// The floating control bar of the inbox card and the routine runner (STYLEGUIDE §2.5, §3.7).
///
/// T12: adopt `.glassEffect()` inside a `GlassEffectContainer` once it can be verified on a Mac.
/// T00 uses `.ultraThinMaterial`, which is visually close and certain to compile.
public struct GlassActionBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Spacing.m) {
            content
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(.ultraThinMaterial, in: Radius.chipShape)
        .padding(.horizontal, Spacing.screenMargin)
    }
}

/// Bottom-anchored undo toast (N6, STYLEGUIDE §3.8). One at a time; a new one replaces the old.
public struct UndoToast: View {
    private let label: String
    private let onUndo: () -> Void

    public init(label: String, onUndo: @escaping () -> Void) {
        self.label = label
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack(spacing: Spacing.m) {
            Text(label).font(Typo.meta).foregroundStyle(Color.ink)
            Button(Copy.undo, action: onUndo)
                .font(Typo.meta)
                .buttonStyle(.plain)
                .foregroundStyle(Color.gtdAccent)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(.ultraThinMaterial, in: Radius.chipShape)
    }
}

/// W1 — setting `waiting` requires who **and** a follow-up date.
///
/// The `+7 days` default is offered as a **suggested** (dashed) chip and is not part of the
/// returned `WaitingInfo` until the user taps it: a default must never be written silently.
public struct WaitingInfoSheet: View {
    private let initial: WaitingInfo?
    private let suggestedWho: [String]
    private let today: Day
    private let onSave: (WaitingInfo) -> Void

    @State private var who: String
    @State private var followUp: Day?
    @Environment(\.dismiss) private var dismiss

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

            TextField("Who or what", text: $who)
                .textFieldStyle(.plain)
                .font(Typo.body)

            if !suggestedWho.isEmpty {
                FlowLayout {
                    ForEach(suggestedWho, id: \.self) { name in
                        Chip(name, state: who == name ? .confirmed : .suggested) { who = name }
                    }
                }
            }

            Text(Copy.followUp).font(Typo.meta).foregroundStyle(Color.textSecondary)
            DateValueChip(
                label: Copy.followUp,
                value: $followUp,
                suggestion: WaitingInfo.suggestedFollowUp(from: today),
                today: today)

            HStack {
                Spacer()
                Button(Copy.done) {
                    guard let followUp, !who.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSave(WaitingInfo(who: who, followUp: followUp))
                    dismiss()
                }
                .disabled(!isComplete)
            }
        }
        .padding(Spacing.cardPadding)
    }

    private var isComplete: Bool {
        followUp != nil && !who.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
#endif
