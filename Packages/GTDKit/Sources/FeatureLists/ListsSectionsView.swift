#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox

/// The Mac content column for the single `Lists` sidebar row (STYLEGUIDE §4.1): every list as a
/// section (header = list name + count), `ListItemRow`s, a quiet `Show done` button at the end of
/// a section that has finished items. Selecting a row opens it in the detail column
/// (`ListItemEditorView`), the same click-or-arrow-keys pattern `ActionListView` uses.
public struct ListsSectionsView: View {
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void

    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    @State private var makeActionTarget: ListItem?

    public init(selection: NoteID? = nil, onOpen: @escaping (NoteID) -> Void) {
        self.selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        let lists = ListsModel(model: model)
        Group {
            if lists.rows.isEmpty {
                ContentUnavailableView(
                    ListsCopy.emptyListsTitle, systemImage: Symbols.listBullet,
                    description: Text(ListsCopy.emptyListsBody))
            } else {
                List(selection: selectionBinding) {
                    ForEach(lists.rows, id: \.list.id) { row in
                        Section {
                            rows(for: row.list.name, lists: lists)
                        } header: {
                            HStack {
                                Text(row.list.name).font(Typo.sectionHeader)
                                Spacer(minLength: Spacing.s)
                                if row.openCount > 0 {
                                    Text("\(row.openCount)")
                                        .font(Typo.counter)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $makeActionTarget) { item in
            MakeActionSheet(model: model, item: item)
        }
    }

    @ViewBuilder private func rows(for list: String, lists: ListsModel) -> some View {
        let open = lists.openItems(in: list)
        let finished = lists.finishedItems(in: list)
        if open.isEmpty && finished.isEmpty {
            Text(Copy.emptyListTitle(list))
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
        } else {
            ForEach(open) { item in
                row(item, lists: lists)
            }
            if !finished.isEmpty {
                if expanded.contains(list) {
                    ForEach(finished) { item in
                        row(item, lists: lists)
                    }
                } else {
                    Button(Copy.showDone) { expanded.insert(list) }
                        .buttonStyle(.plain)
                        .font(Typo.meta)
                        .foregroundStyle(Color.gtdAccent)
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: ListItem, lists: ListsModel) -> some View {
        ListItemRow(item: item, onComplete: item.isFinished ? nil : {
            Task { await lists.complete(item.id) }
        })
        .contentShape(Rectangle())
        .tag(item.id)
        .contextMenu {
            Button {
                makeActionTarget = item
            } label: {
                Label(ListsCopy.makeAction, systemImage: Symbols.makeAction)
            }
            Button(role: .destructive) {
                Task { await lists.trash(item.id) }
            } label: {
                Label(Copy.trash, systemImage: Symbols.trash)
            }
        }
    }

    private var selectionBinding: Binding<NoteID?> {
        Binding(
            get: { selection },
            set: { if let id = $0 { onOpen(id) } })
    }
}
#endif
