#if canImport(SwiftUI)
import SwiftUI
import GTDModel

/// A `DateValueChip` in the smallest sheet that can hold one (STYLEGUIDE §3.1: the chip's own
/// popover on the Mac, a `.medium` sheet on iOS). Used where a defer date is asked for outside
/// a card: a row's `Defer` menu item and a drop onto Deferred (R-2 — Deferred is a date, not a
/// status). Nothing is written until `Done`; `Cancel` leaves the note as it was.
public struct DeferDateSheet: View {
    private let today: Day
    private let onConfirm: (Day?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Day?

    public init(initial: Day?, today: Day, onConfirm: @escaping (Day?) -> Void) {
        self.today = today
        self.onConfirm = onConfirm
        _value = State(initialValue: initial)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.deferLabel).font(Typo.sectionHeader)
            DateValueChip(label: Copy.deferLabel, value: $value, today: today)
            HStack {
                Button(Copy.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Copy.done) {
                    onConfirm(value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.cardPadding)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
#endif
