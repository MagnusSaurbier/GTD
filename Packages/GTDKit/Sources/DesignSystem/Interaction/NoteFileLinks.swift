#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore

/// "Open in Obsidian" and "Copy path" for one note, the quiet row at the bottom of the action
/// and project detail views. No vault root (fixtures) means no link Obsidian could resolve and no
/// path worth copying: the row renders nothing.
public struct NoteFileLinks: View {
    private let note: NoteID
    @Environment(\.openURL) private var openURL
    @Environment(\.vaultRootPath) private var vaultRootPath

    public init(note: NoteID) {
        self.note = note
    }

    public var body: some View {
        if let url = ObsidianLink.url(for: note, vaultRoot: vaultRootPath),
           let path = ObsidianLink.filePath(for: note, vaultRoot: vaultRootPath) {
            HStack(spacing: Spacing.l) {
                Button {
                    openURL(url)
                } label: {
                    Label(Copy.openInObsidian, systemImage: Self.openExternallySymbol)
                }
                Button {
                    Clipboard.copy(path)
                } label: {
                    Label(Copy.copyPath, systemImage: Self.copySymbol)
                }
            }
            .buttonStyle(.plain)
            .font(Typo.meta)
            .foregroundStyle(Color.textSecondary)
        }
    }

    // Plain chrome affordances, not STYLEGUIDE §7 concepts, so they stay out of `Symbols`.
    /// Also the action detail's "Open project" button (#72): one "open" glyph in the app.
    public static let openExternallySymbol = "arrow.up.forward.app"
    private static let copySymbol = "doc.on.doc"
}
#endif
