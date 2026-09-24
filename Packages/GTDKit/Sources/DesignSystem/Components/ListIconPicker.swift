#if canImport(SwiftUI)
import SwiftUI

/// The grid behind Settings → Lists' icon button: every `Symbols.listIconChoices` symbol, the
/// current one marked, and a way back to the built-in glyph. Picking closes the sheet.
public struct ListIconPicker: View {
    let listName: String
    let current: String
    let builtIn: String
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    /// `current` is what the list shows now; `builtIn` is `Symbols.list(named:)` — picking it
    /// clears the stored choice instead of storing the default.
    public init(listName: String, current: String, builtIn: String, onPick: @escaping (String?) -> Void) {
        self.listName = listName
        self.current = current
        self.builtIn = builtIn
        self.onPick = onPick
    }

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: Spacing.s)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(Symbols.listIconChoices) { group in
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text(group.title).font(Typo.meta).foregroundStyle(Color.textSecondary)
                            LazyVGrid(columns: columns, spacing: Spacing.s) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    cell(symbol)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .navigationTitle("Icon for \(listName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Default") { pick(nil) }
                        .disabled(current == builtIn)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 440, idealHeight: 520)
        #endif
    }

    private func cell(_ symbol: String) -> some View {
        let isCurrent = symbol == current
        return Button { pick(symbol == builtIn ? nil : symbol) } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .foregroundStyle(isCurrent ? Color.gtdAccent : Color.ink)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? Color.gtdAccent.opacity(0.15) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isCurrent ? Color.gtdAccent : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func pick(_ symbol: String?) {
        onPick(symbol)
        dismiss()
    }
}
#endif
