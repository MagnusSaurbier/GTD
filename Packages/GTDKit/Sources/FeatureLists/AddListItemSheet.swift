#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// The `+` inside a list (L1): one field, one button, the same shape as the shell's quick
/// capture. It sends `ListsModel.add`; a refusal (empty title, taken title) is `AppModel.perform`'s
/// to show, so the sheet only closes when the item exists.
struct AddListItemSheet: View {
    let list: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(ListsCopy.addTo(list))
                .font(Typo.sectionHeader)
                .foregroundStyle(Color.ink)
            TextField(ListsCopy.newItemPlaceholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.cardText)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
            HStack {
                Button(Copy.cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button(ListsCopy.add, action: add)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gtdAccent)
                    .disabled(!ListsModel.canAdd(title))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.screenMargin)
        .frame(minWidth: 320)
        #if os(iOS)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { focused = true }
    }

    private func add() {
        guard ListsModel.canAdd(title) else { return }
        let lists = ListsModel(model: model)
        Task {
            if await lists.add(title, to: list) { dismiss() }
        }
    }
}
#endif
