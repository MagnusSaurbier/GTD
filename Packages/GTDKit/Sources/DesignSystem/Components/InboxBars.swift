#if canImport(SwiftUI)
import SwiftUI

/// Step-1 bar of the inbox card (STYLEGUIDE §3.6, decision #12): three **equal, neutral**
/// labelled buttons — symbol over text — and **none of them is accent-filled**, because the app
/// does not know the right answer yet and must not look like it suggests one (§1.2). iPhone: a
/// floating glass capsule pinned above the home indicator (`GlassActionBar`). Mac: a row of
/// stock bordered buttons under the card — the same three targets, same order.
public struct StepOneBar: View {
    private let onAction: () -> Void
    private let onKnowledgeOrList: () -> Void
    private let onTrash: () -> Void
    private let highlighted: Int?

    /// `highlighted` — the button (0 Action, 1 Knowledge / List, 2 Trash) carrying the Mac
    /// keyboard walk's semi-highlight (#77), if any.
    public init(
        highlighted: Int? = nil,
        onAction: @escaping () -> Void,
        onKnowledgeOrList: @escaping () -> Void,
        onTrash: @escaping () -> Void
    ) {
        self.highlighted = highlighted
        self.onAction = onAction
        self.onKnowledgeOrList = onKnowledgeOrList
        self.onTrash = onTrash
    }

    public var body: some View {
        #if os(macOS)
        HStack(spacing: Spacing.m) { buttons }
        #else
        GlassActionBar { buttons }
        #endif
    }

    @ViewBuilder private var buttons: some View {
        target(Copy.actionKind, symbol: Symbols.actionKind, index: 0, action: onAction)
        target(
            Copy.knowledgeOrList, symbol: Symbols.knowledgeOrListKind, index: 1,
            action: onKnowledgeOrList)
        target(Copy.trash, symbol: Symbols.trash, index: 2, action: onTrash)
    }

    @ViewBuilder private func target(
        _ title: String, symbol: String, index: Int, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                Text(title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .font(Typo.chip)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        .keyHighlight(highlighted == index, in: RoundedRectangle(cornerRadius: 10))
        #else
        .buttonStyle(.plain)
        #endif
    }
}

/// The opened action card's bar (STYLEGUIDE §3.6): `Waiting` and `Done` as labelled buttons, a
/// trailing `⋯` menu (`File to`) that repeats the two swipe targets (Next / Someday) for
/// one-handed and AX use. While a text field has the keyboard, the whole bar is replaced by a
/// single `Done` button that blurs the field instead.
public struct ActionCardBar: View {
    private let isFieldFocused: Bool
    private let onWaiting: () -> Void
    private let onDone: () -> Void
    private let onFileToNext: () -> Void
    private let onFileToSomeday: () -> Void
    private let onDismissKeyboard: () -> Void

    public init(
        isFieldFocused: Bool,
        onWaiting: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onFileToNext: @escaping () -> Void,
        onFileToSomeday: @escaping () -> Void,
        onDismissKeyboard: @escaping () -> Void = {}
    ) {
        self.isFieldFocused = isFieldFocused
        self.onWaiting = onWaiting
        self.onDone = onDone
        self.onFileToNext = onFileToNext
        self.onFileToSomeday = onFileToSomeday
        self.onDismissKeyboard = onDismissKeyboard
    }

    public var body: some View {
        GlassActionBar {
            if isFieldFocused {
                Spacer(minLength: 0)
                Button(Copy.done, action: onDismissKeyboard)
                    .font(Typo.chip)
                    .foregroundStyle(Color.ink)
            } else {
                Button(action: onWaiting) {
                    Label(Copy.waiting, systemImage: Symbols.waiting)
                }
                Button(action: onDone) {
                    Label(Copy.done, systemImage: Symbols.done)
                }
                Spacer(minLength: Spacing.s)
                Menu {
                    Button(Copy.next, systemImage: Symbols.next, action: onFileToNext)
                    Button(Copy.someday, systemImage: Symbols.someday, action: onFileToSomeday)
                } label: {
                    Image(systemName: Symbols.more)
                }
                .accessibilityLabel(Copy.fileTo)
            }
        }
        .font(Typo.chip)
        .foregroundStyle(Color.ink)
        .labelStyle(.titleAndIcon)
    }
}

/// The Knowledge/List card's navbar (STYLEGUIDE §3.6): a **fixed row with stable positions**
/// computed by `NavbarLayout.slots(favourites:platform:)` — `Knowledge` first, then the
/// favourite lists in Settings order, then `More…`. Positions never reorder by use; a list slot
/// files the card at once (undoable), `Knowledge` and `More…` open a sheet.
public struct KnowledgeListNavbar: View {
    @Environment(\.listIcons) private var listIcons
    private let slots: [NavbarSlot]
    private let onKnowledge: () -> Void
    private let onList: (String) -> Void
    private let onMore: () -> Void
    private let highlighted: Int?

    /// `highlighted` — the slot carrying the Mac keyboard walk's semi-highlight (#77), if any.
    public init(
        favourites: [String],
        platform: NavbarPlatform,
        highlighted: Int? = nil,
        onKnowledge: @escaping () -> Void,
        onList: @escaping (String) -> Void,
        onMore: @escaping () -> Void
    ) {
        self.slots = NavbarLayout.slots(favourites: favourites, platform: platform)
        self.onKnowledge = onKnowledge
        self.onList = onList
        self.onMore = onMore
        self.highlighted = highlighted
    }

    public var body: some View {
        GlassActionBar {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                Button(action: { tap(slot) }) {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: symbol(for: slot)).symbolRenderingMode(.hierarchical)
                        Text(label(for: slot))
                    }
                    .font(Typo.chip)
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                .keyHighlight(highlighted == index, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(label(for: slot))
            }
        }
    }

    private func tap(_ slot: NavbarSlot) {
        switch slot.kind {
        case .knowledge: onKnowledge()
        case let .list(name): onList(name)
        case .more: onMore()
        }
    }

    private func symbol(for slot: NavbarSlot) -> String {
        switch slot.kind {
        case .knowledge: Symbols.knowledge
        case let .list(name): Symbols.list(named: name, icons: listIcons)
        case .more: Symbols.more
        }
    }

    private func label(for slot: NavbarSlot) -> String {
        switch slot.kind {
        case .knowledge: Copy.knowledge
        case let .list(name): name
        case .more: Copy.more
        }
    }
}
#endif
