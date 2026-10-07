#if canImport(SwiftUI)
import SwiftUI
import GTDAppCore

// #94 — a dialog's field keeps what was typed in `InputDrafts` and gets it back when the dialog
// opens again. The rules (when a draft is cleared) are `InputDrafts`'; this only wires a value
// to its key.

public extension View {
    /// Keeps `value` under `key` while it changes, and restores the kept value whenever `key`
    /// becomes current (the dialog appears, or the view is handed another note). `isEmpty`
    /// says when there is nothing to keep (the draft is cleared then); `whenNone`, if given, is
    /// what the value becomes for a key without a draft — a field reused across notes (the
    /// project's `New step`) starts empty instead of showing the previous note's text.
    func keepsDraft<Value: Codable & Equatable>(
        _ value: Binding<Value>,
        key: String?,
        in drafts: InputDrafts?,
        isEmpty: @escaping (Value) -> Bool,
        whenNone: Value? = nil
    ) -> some View {
        modifier(DraftKeeper(value: value, key: key, drafts: drafts, isEmpty: isEmpty, whenNone: whenNone))
    }

    /// A text field's draft: blank text is nothing to keep.
    func keepsDraft(
        _ text: Binding<String>,
        key: String?,
        in drafts: InputDrafts?,
        whenNone: String? = nil
    ) -> some View {
        keepsDraft(text, key: key, in: drafts, isEmpty: InputDrafts.isBlank, whenNone: whenNone)
    }
}

private struct DraftKeeper<Value: Codable & Equatable>: ViewModifier {
    let value: Binding<Value>
    let key: String?
    let drafts: InputDrafts?
    let isEmpty: (Value) -> Bool
    let whenNone: Value?

    /// The key whose draft the field shows. A change of the value is kept only under it, so
    /// the update that switches keys (and may change the value in the same pass) can never
    /// write one note's text under another note's key, or clear a draft before it is restored.
    @State private var shownKey: String??

    func body(content: Content) -> some View {
        content
            .onChange(of: key, initial: true) { _, key in restore(key) }
            .onChange(of: value.wrappedValue) { _, _ in
                guard let drafts, let key, shownKey == .some(key) else { return }
                // The value as it is now, not the one this change reported: a restore in the
                // same pass may already have replaced it.
                let current = value.wrappedValue
                drafts.keep(isEmpty(current) ? nil : current, for: key)
            }
    }

    private func restore(_ key: String?) {
        shownKey = .some(key)
        guard let drafts, let key else { return }
        if let saved = drafts.value(Value.self, for: key) {
            if saved != value.wrappedValue { value.wrappedValue = saved }
        } else if let whenNone, whenNone != value.wrappedValue {
            value.wrappedValue = whenNone
        }
    }
}
#endif
