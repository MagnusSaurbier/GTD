#if canImport(SwiftUI)
import SwiftUI

/// The keys of the keyboard walk (#65, #77) for a screen that walks its own stops — the inbox's
/// sheets, the waiting sheet. The view it wraps takes key focus (bound to `focus`, so the owner
/// can hand it back after a text field), and while it has it:
///
/// - `Tab` / `⇧Tab` call `onMove(+1)` / `onMove(-1)` (`⇧Tab` arrives either as a shifted tab or as
///   the back-tab character, depending on the layout);
/// - `↩` calls `onPress`, `⌘↩` calls `onNextRow` (ignored when `nil`);
/// - `→` / `←` call `onArrow(+1)` / `onArrow(-1)` when given (a tree row opens / closes).
///
/// `Esc` is left alone: in a sheet it is the stock Cancel. A focused text field keeps every key,
/// so typing is never taken over. Mac only — on iOS the modifier changes nothing.
public struct KeyWalkKeys: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let onMove: (Int) -> Void
    let onPress: () -> Void
    let onNextRow: (() -> Void)?
    let onArrow: ((Int) -> Void)?

    public func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusable()
            .focused(focus)
            .focusEffectDisabled()
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                let backward = press.modifiers.contains(.shift) || press.characters == "\u{19}"
                onMove(backward ? -1 : 1)
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    guard let onNextRow else { return .ignored }
                    onNextRow()
                } else {
                    onPress()
                }
                return .handled
            }
            .onKeyPress(keys: [.rightArrow, .leftArrow], phases: .down) { press in
                guard let onArrow else { return .ignored }
                onArrow(press.key == .rightArrow ? 1 : -1)
                return .handled
            }
            .onAppear { focus.wrappedValue = true }
        #else
        content
        #endif
    }
}

public extension View {
    /// See `KeyWalkKeys`.
    func keyWalkKeys(
        focus: FocusState<Bool>.Binding,
        onMove: @escaping (Int) -> Void,
        onPress: @escaping () -> Void,
        onNextRow: (() -> Void)? = nil,
        onArrow: ((Int) -> Void)? = nil
    ) -> some View {
        modifier(KeyWalkKeys(
            focus: focus, onMove: onMove, onPress: onPress, onNextRow: onNextRow,
            onArrow: onArrow))
    }
}

/// The walking keys as a quiet line under a sheet's content (STYLEGUIDE §3.6) — the sheet
/// counterpart of the inbox's key legend. Mac only; nothing on iOS, which has no walk.
public struct KeyWalkLegendLine: View {
    private let text: String

    public init(press: String, hasNextRow: Bool, back: String? = Copy.cancel) {
        text = KeyWalkLegend.string(press: press, hasNextRow: hasNextRow, back: back)
    }

    public var body: some View {
        #if os(macOS)
        Text(text)
            .font(Typo.counter)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .accessibilityLabel(text)
        #else
        EmptyView()
        #endif
    }
}
#endif
