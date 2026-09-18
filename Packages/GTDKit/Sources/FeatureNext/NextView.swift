#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// The default screen (E1/E2). **Owned by T21** — this is the compiling shell.
public struct NextView: View {
    private let mode: NextViewMode
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(mode: NextViewMode, onOpen: @escaping (NoteID) -> Void) {
        self.mode = mode
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = NextListModel(model: model, mode: mode)
        Group {
            if list.items.isEmpty, list.chase.isEmpty {
                ContentUnavailableView(Copy.emptyNextTitle, systemImage: Symbols.next,
                                       description: Text(Copy.emptyNextBody))
            } else {
                List {
                    if !list.chase.isEmpty {
                        Section(Copy.chase) {
                            ForEach(list.chase, id: \.id) { row(list, $0) }
                        }
                    }
                    Section {
                        ForEach(list.items, id: \.id) { row(list, $0) }
                    }
                }
            }
        }
        .navigationTitle(Copy.next)
    }

    private func row(_ list: NextListModel, _ action: Action) -> some View {
        ActionRow(
            action: action,
            projectTitle: list.projectTitle(for: action),
            badges: list.badges(for: action),
            onComplete: { Task { try? await model.send(.complete(action.id)) } })
            .contentShape(Rectangle())
            .onTapGesture { onOpen(action.id) }
    }
}

#Preview {
    NavigationStack {
        NextView(mode: .full, onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}
#endif
