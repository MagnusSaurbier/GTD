#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox

/// The iPhone Lists tab (STYLEGUIDE §4.2, L5): a stock `List` of lists with counts. Tapping a
/// row pushes `ListItemsView`; the tab's `NavigationStack` and `.navigationDestination(for:
/// ListsRoute.self)` live in `App/PhoneShell`, exactly as the Next tab's push does.
public struct ListsHomeView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        let lists = ListsModel(model: model)
        Group {
            if lists.rows.isEmpty {
                ContentUnavailableView(
                    ListsCopy.emptyListsTitle, systemImage: Symbols.listBullet,
                    description: Text(ListsCopy.emptyListsBody))
            } else {
                List {
                    ForEach(lists.rows, id: \.list.id) { row in
                        NavigationLink(value: ListsRoute.list(row.list.name)) {
                            HStack {
                                Label(row.list.name, systemImage: Symbols.list(named: row.list.name))
                                    .font(Typo.body)
                                    .foregroundStyle(Color.ink)
                                Spacer(minLength: Spacing.s)
                                if row.openCount > 0 {
                                    Text("\(row.openCount)")
                                        .font(Typo.counter)
                                        .foregroundStyle(Color.textSecondary)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityLabel(Copy.spoken(
                            [row.list.name, row.openCount > 0 ? "\(row.openCount)" : ""]))
                    }
                }
            }
        }
        .navigationTitle(Copy.lists)
    }
}

/// One list's items (L1, L3): completion circle + title only rows (§3.3), trailing swipe
/// `Done`, context menu `Make action` / `Trash`, a quiet `Show done` button revealing
/// `Lists/<name>/Done/` when it has entries. Tapping a row pushes the item editor.
public struct ListItemsView: View {
    private let list: String

    @Environment(AppModel.self) private var model
    @State private var showDone = false
    @State private var makeActionTarget: ListItem?

    public init(list: String) {
        self.list = list
    }

    public var body: some View {
        let lists = ListsModel(model: model)
        let open = lists.openItems(in: list)
        let finished = lists.finishedItems(in: list)
        Group {
            if open.isEmpty && finished.isEmpty {
                ContentUnavailableView(Copy.emptyListTitle(list), systemImage: Symbols.list(named: list))
            } else {
                List {
                    ForEach(open) { item in
                        row(item, lists: lists)
                    }
                    if !finished.isEmpty {
                        if showDone {
                            ForEach(finished) { item in
                                row(item, lists: lists)
                            }
                        } else {
                            Button(Copy.showDone) { showDone = true }
                                .buttonStyle(.plain)
                                .font(Typo.meta)
                                .foregroundStyle(Color.gtdAccent)
                        }
                    }
                }
            }
        }
        .navigationTitle(list)
        .sheet(item: $makeActionTarget) { item in
            MakeActionSheet(model: model, item: item)
        }
    }

    @ViewBuilder private func row(_ item: ListItem, lists: ListsModel) -> some View {
        NavigationLink(value: ListsRoute.item(item.id)) {
            ListItemRow(item: item, onComplete: item.isFinished ? nil : {
                Task { await lists.complete(item.id) }
            })
        }
        .swipeActions(edge: .trailing) {
            if !item.isFinished {
                Button {
                    Task { await lists.complete(item.id) }
                } label: {
                    Label(Copy.done, systemImage: Symbols.done)
                }
                .tint(Color.signalDone)
            }
        }
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
}

/// Title + notes editor (STYLEGUIDE §4.1/§4.2: "the note editor (title + notes)"), shared by the
/// iPhone push destination and the Mac detail column. All the autosave logic is
/// `ListItemEditModel`'s; this view is only the surface (ARCHITECTURE §5).
public struct ListItemEditorView: View {
    private let item: NoteID

    public init(item: NoteID) {
        self.item = item
    }

    public var body: some View {
        ListItemEditor(id: item)
    }
}

private struct ListItemEditor: View {
    let id: NoteID

    @Environment(AppModel.self) private var model
    @State private var editor: ListItemEditModel?
    @State private var makeActionTarget: ListItem?
    @FocusState private var focus: TextEntry?
    @State private var titleGeneration = 0

    private enum TextEntry: Hashable { case title, notes }

    var body: some View {
        Group {
            if let editor, let draft = editor.draft {
                form(editor, draft: draft)
            } else if editor?.isMissing == true {
                ContentUnavailableView(
                    ListsCopy.missingItemTitle, systemImage: Symbols.trash,
                    description: Text(ListsCopy.missingItemBody))
            } else {
                Color.clear
            }
        }
        .task(id: id) {
            if let editor, editor.id == id { return }
            editor = ListItemEditModel(model: model, id: id)
        }
        .onChange(of: model.snapshot) { _, _ in
            editor?.refresh()
        }
        .onDisappear {
            let leaving = editor
            Task { await leaving?.flush() }
        }
    }

    @ViewBuilder private func form(_ editor: ListItemEditModel, draft: ListItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                TextField(
                    ListsCopy.titlePlaceholder,
                    text: Binding(
                        get: { editor.title },
                        set: { submitTitleIfAsked(editor.setTitle($0)) }),
                    axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.screenTitle)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1...4)
                    .fixedSize(horizontal: false, vertical: true)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .id(titleGeneration)

                if editor.lastError != nil {
                    errorBanner(editor)
                }

                TextField(
                    "",
                    text: Binding(get: { editor.notes }, set: { editor.setNotes($0) }),
                    prompt: Text(ListsCopy.notesPlaceholder).foregroundStyle(Color.textTertiary),
                    axis: .vertical)
                    .textFieldStyle(.plain)
                    .listEditingShortcuts()
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(3...)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focus, equals: .notes)
                    .accessibilityLabel(ListsCopy.notesPlaceholder)
            }
            .padding(Spacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focus = nil }
        }
        .onChange(of: focus) { _, entry in
            editor.setTitleHeld(entry == .title)
            if entry == nil { Task { await editor.flush() } }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Copy.done) { focus = nil }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    focus = nil
                    makeActionTarget = draft
                } label: {
                    Label(ListsCopy.makeAction, systemImage: Symbols.makeAction)
                }
            }
        }
        .sheet(item: $makeActionTarget) { item in
            MakeActionSheet(model: model, item: item)
        }
    }

    private func submitTitleIfAsked(_ submitted: Bool) {
        guard submitted else { return }
        focus = nil
        titleGeneration += 1
    }

    @ViewBuilder private func errorBanner(_ editor: ListItemEditModel) -> some View {
        Text(errorTitle(editor.lastError))
            .font(Typo.meta)
            .foregroundStyle(Color.ink)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fillQuiet, in: Radius.chipShape)
    }

    private func errorTitle(_ error: (any Error)?) -> String {
        switch error as? GTDError {
        case .titleCollision: ListsCopy.titleTaken
        case .notFound: ListsCopy.missingItemTitle
        default: ListsCopy.notSaved
        }
    }
}
#endif
