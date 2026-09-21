#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox

/// L4 "Make action": the opened action card, as a sheet, for one list item.
///
/// A host and nothing more: the card, its bar, its sub-sheets and every decision are
/// `FeatureInbox.MakeActionCardView` over `MakeActionModel` — the same card the inbox opens in
/// step 2a, so the asterisk rule, the chips and the cap flow exist once.
public struct MakeActionSheet: View {
    @State private var makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.keyBindings) private var keyBindings

    public init(model: AppModel, item: ListItem) {
        _makeAction = State(initialValue: MakeActionModel(model: model, item: item))
    }

    public var body: some View {
        NavigationStack {
            MakeActionCardView(model: makeAction) { dismiss() }
        }
        .onChange(of: keyBindings, initial: true) { _, bindings in
            makeAction.keyBindings = bindings
        }
    }
}
#endif
