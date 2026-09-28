#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore

/// Text an earlier run never saved (#56): which note, when, and what was typed — read-only and
/// selectable — with Restore (writes it into the note), Copy text and Discard.
///
/// A global flow like the conflict sheet (STYLEGUIDE §4.3): the shell presents it at launch,
/// one entry at a time, until the journal has none left. A click outside or a swipe must not
/// make the decision for the person, so interactive dismissal is off; Escape is Discard's
/// neighbour on purpose — it only closes via Restore or Discard.
public struct UnsavedTextSheet: View {
    private let entry: UnsavedText
    private let position: (index: Int, total: Int)
    /// False when the note is gone: only copying is left.
    private let canRestore: Bool
    private let onRestore: () -> Void
    private let onDiscard: () -> Void

    @State private var copied = false

    public init(
        entry: UnsavedText,
        position: (index: Int, total: Int) = (1, 1),
        canRestore: Bool,
        onRestore: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.entry = entry
        self.position = position
        self.canRestore = canRestore
        self.onRestore = onRestore
        self.onDiscard = onDiscard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.unsavedTitle).font(Typo.sectionHeader)
                Spacer()
                if position.total > 1 {
                    Text(Copy.unsavedCounter(position.index, of: position.total))
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Text(canRestore
                 ? Copy.unsavedBody(note: entry.displayTitle)
                 : Copy.unsavedNoteGone(note: entry.note.title))
                .font(Typo.meta)
                .foregroundStyle(canRestore ? Color.textSecondary : Color.signalAttention)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.unsavedTyped).font(Typo.meta).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(entry.savedAt, format: .dateTime.day().month().hour().minute())
                        .font(Typo.meta)
                        .foregroundStyle(Color.textTertiary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        if let title = entry.title {
                            Text(title).font(Typo.sectionHeader)
                        }
                        if let text = entry.text {
                            Text(text).font(Typo.meta.monospaced())
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
                }
                .frame(minHeight: SheetMetrics.mergedTextMinHeight)
                .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Radius.tile))
                .accessibilityLabel(Copy.unsavedTyped)
            }

            HStack {
                Button(Copy.discard, role: .destructive, action: onDiscard)
                Spacer()
                Button(copied ? Copy.copied : Copy.copyText) {
                    Clipboard.copy(entry.copyText)
                    copied = true
                }
                Button(Copy.restore, action: onRestore)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRestore)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(
            minWidth: SheetMetrics.minWidth, idealWidth: SheetMetrics.wideIdealWidth * 0.7,
            minHeight: SheetMetrics.minHeight, idealHeight: SheetMetrics.idealHeight)
        #endif
        .interactiveDismissDisabled()
        // A new entry is a new sheet body: "Copied" belongs to the one that was copied.
        .onChange(of: entry) { _, _ in copied = false }
    }
}

// MARK: - Previews

private let previewEntry = UnsavedText(
    kind: .action, path: "Actions/Call the bank.md", title: nil,
    text: "# Why?\nThe fee is wrong and it happened twice.\n\n# What?\n- [ ] Find the statement\n- [ ] Call them",
    savedAt: Date())

#Preview("Restore") {
    UnsavedTextSheet(entry: previewEntry, position: (1, 2), canRestore: true,
                     onRestore: {}, onDiscard: {})
}

#Preview("Note gone — dark") {
    UnsavedTextSheet(entry: previewEntry, canRestore: false, onRestore: {}, onDiscard: {})
        .preferredColorScheme(.dark)
}
#endif
