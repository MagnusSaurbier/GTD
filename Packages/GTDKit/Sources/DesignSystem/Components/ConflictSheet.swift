#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore

/// The stale-write conflict sheet (N3, ARCHITECTURE §6 2026-09-25): both versions of the note
/// side by side, read-only, and under them the merged one — title and text — which the person
/// edits and writes with Done. The other exit keeps the vault's version, which is what the
/// vault already holds: the refused write was reverted before this sheet opened.
///
/// It is a global flow (the shell presents it, STYLEGUIDE §4.3), so nothing here knows which
/// screen the person was on. Done is `⌘↩`, keeping the vault's version is Escape.
public struct ConflictSheet: View {
    private let conflict: WriteConflict
    private let suggestion: MergeSuggestion
    private let onDone: (_ path: String, _ text: String) -> Void
    private let onKeepVault: () -> Void

    @State private var title: String
    @State private var text: String

    public init(
        conflict: WriteConflict,
        onDone: @escaping (_ path: String, _ text: String) -> Void,
        onKeepVault: @escaping () -> Void
    ) {
        self.conflict = conflict
        self.suggestion = conflict.suggestion
        self.onDone = onDone
        self.onKeepVault = onKeepVault
        _title = State(initialValue: NoteID(path: conflict.suggestion.path).title)
        _text = State(initialValue: conflict.suggestion.text)
    }

    private var mergedPath: String? {
        MergedNote.path(folder: NoteID(path: suggestion.path).folder, title: title)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.conflictTitle).font(Typo.sectionHeader)
            Text(Copy.conflictBody(label: conflict.label))
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.l) { versions }
                VStack(alignment: .leading, spacing: Spacing.l) { versions }
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(Copy.conflictMerged).font(Typo.meta).foregroundStyle(Color.textSecondary)
                TextField(Copy.titlePlaceholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(Typo.sectionHeader)
                    .accessibilityLabel(Copy.titlePlaceholder)
                TextEditor(text: $text)
                    .font(Typo.body.monospaced())
                    .frame(minHeight: SheetMetrics.mergedTextMinHeight)
                    .overlay(RoundedRectangle(cornerRadius: Radius.tile).stroke(Color.hairline))
                    .accessibilityLabel(Copy.conflictMerged)
                if suggestion.conflicts > 0 {
                    Label(Copy.conflictHunks(suggestion.conflicts), systemImage: Symbols.overdue)
                        .font(Typo.meta)
                        .foregroundStyle(Color.signalAttention)
                }
            }

            HStack {
                Button(Copy.keepVaultVersion, action: onKeepVault)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Copy.done) {
                    guard let mergedPath else { return }
                    onDone(mergedPath, text)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(mergedPath == nil)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(macOS)
        .frame(
            minWidth: SheetMetrics.wideMinWidth, idealWidth: SheetMetrics.wideIdealWidth,
            minHeight: SheetMetrics.minHeight, idealHeight: SheetMetrics.wideIdealHeight)
        #endif
        // A swipe or a click outside must not throw away what the person typed into the merge.
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var versions: some View {
        VersionPanel(
            heading: Copy.conflictMine, path: conflict.path, text: conflict.mine,
            absent: Copy.conflictTrashedHere)
        VersionPanel(
            heading: Copy.conflictTheirs, path: conflict.theirsPath, text: conflict.theirs,
            absent: Copy.conflictGoneFromVault)
    }
}

/// One read-only side of the conflict: where the note is and what it says.
private struct VersionPanel: View {
    let heading: String
    let path: String?
    let text: String?
    let absent: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(heading).font(Typo.meta).foregroundStyle(Color.textSecondary)
            Text(path.map { NoteID(path: $0).title } ?? absent)
                .font(Typo.sectionHeader)
                .lineLimit(2)
            ScrollView {
                Text(text ?? absent)
                    .font(Typo.meta.monospaced())
                    .foregroundStyle(text == nil ? Color.textTertiary : Color.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
            }
            .frame(minHeight: SheetMetrics.versionPanelMinHeight, maxHeight: SheetMetrics.versionPanelMaxHeight)
            .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Radius.tile))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private let previewConflict = WriteConflict(
    label: "Edit “Call the bank”",
    basePath: "Actions/Call the bank.md",
    base: "---\nstatus: next\n---\n# Why?\nThe fee is wrong.\n# What?\nCall them.\n",
    path: "Actions/Call the bank.md",
    mine: "---\nstatus: next\n---\n# Why?\nThe fee is wrong and it happened twice.\n# What?\nCall them.\n",
    theirsPath: "Actions/Call the bank about the fee.md",
    theirs: "---\nstatus: next\n---\n# Why?\nThe fee is wrong.\n# What?\nCall them.\n")

#Preview("Rename elsewhere, edit here") {
    ConflictSheet(conflict: previewConflict, onDone: { _, _ in }, onKeepVault: {})
}

#Preview("Both changed the same line — dark") {
    var both = previewConflict
    both.theirs = "---\nstatus: someday\n---\n# Why?\nThe fee was refunded.\n# What?\nCall them.\n"
    return ConflictSheet(conflict: both, onDone: { _, _ in }, onKeepVault: {})
        .preferredColorScheme(.dark)
}

#Preview("Trashed here — AX1") {
    var trashed = previewConflict
    trashed.mine = nil
    return ConflictSheet(conflict: trashed, onDone: { _, _ in }, onKeepVault: {})
        .dynamicTypeSize(.accessibility1)
}
#endif
