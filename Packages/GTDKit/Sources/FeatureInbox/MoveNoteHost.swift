#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

extension View {
    /// Makes this screen the place where a dragged row (or `Move to…`) lands: sets the
    /// `moveNote` environment for every row and drop target below, and presents the dialogue a
    /// drop needs — the action card, the defer-date sheet or the project picker — over
    /// `coordinator`. The Mac shell applies it to the whole window, the iPhone to its Next tab.
    public func moveNoteHost(_ coordinator: MoveCoordinator? = nil) -> some View {
        modifier(MoveNoteHostModifier(injected: coordinator))
    }
}

private struct MoveNoteHostModifier: ViewModifier {
    /// A coordinator the shell shares with something else, or `nil` for one of our own — made
    /// on first appearance, because it needs the `AppModel` from the environment.
    let injected: MoveCoordinator?
    @State private var owned: MoveCoordinator?
    @Environment(AppModel.self) private var model
    @Environment(\.keyBindings) private var keyBindings

    private var coordinator: MoveCoordinator? { injected ?? owned }

    func body(content: Content) -> some View {
        content
            .environment(\.moveNote, coordinator.map { coordinator in
                MoveNoteHandler(
                    accepts: { id, destination in coordinator.accepts(id, destination) },
                    move: { id, destination in
                        Task { await coordinator.move(id, to: destination) }
                    },
                    beginDrag: { id in coordinator.dragging = id },
                    currentDrag: { coordinator.dragging })
            })
            .onAppear {
                if injected == nil, owned == nil {
                    owned = MoveCoordinator(model: model, bindings: keyBindings)
                }
            }
            .onChange(of: keyBindings, initial: true) { _, bindings in
                coordinator?.keyBindings = bindings
            }
            .sheet(item: dialogueBinding) { dialogue in
                if let coordinator { sheet(dialogue, coordinator) }
            }
    }

    private var dialogueBinding: Binding<MoveCoordinator.Dialogue?> {
        Binding(get: { coordinator?.dialogue }, set: { coordinator?.dialogue = $0 })
    }

    @ViewBuilder
    private func sheet(_ dialogue: MoveCoordinator.Dialogue, _ coordinator: MoveCoordinator) -> some View {
                switch dialogue {
                case let .card(model):
                    NavigationStack {
                        MakeActionCardView(model: model) { coordinator.cancel() }
                    }
                case let .pickList(action):
                    ListChoiceSheet(
                        lists: coordinator.allLists,
                        hasNoLists: coordinator.hasNoLists,
                        listsFolderName: coordinator.listsFolderName,
                        newListRefusal: coordinator.newListRefusal,
                        onChoose: { name in Task { await coordinator.chooseList(action, named: name) } },
                        onCreate: { name in Task { await coordinator.createListAndMove(action, named: name) } },
                        onNameChanged: { coordinator.clearNewListRefusal() },
                        onCancel: { coordinator.cancel() },
                        drafts: model.inputDrafts)
                    #if os(iOS)
                        .presentationDetents([.medium, .large])
                    #endif
                case let .pickProject(action):
                    ProjectChoiceSheet(
                        picker: { coordinator.projectPicker(search: $0) },
                        current: action.project,
                        onChoose: { project in
                            Task { await coordinator.chooseProject(action, project) }
                        },
                        onCreate: { title in
                            Task { await coordinator.createProject(action, named: title) }
                        },
                        onCancel: { coordinator.cancel() })
                    #if os(iOS)
                        .presentationDetents([.medium, .large])
                    #endif
                }
    }
}

/// The project picker as a sheet, over a `ProjectPickerModel` provider: search, `Clear`, one
/// row per project (grouped by area), the `Create project "<text>"` row (R-8). Shared by the
/// action card's `+ project` chip and a drop onto the Projects section, so the picker's rules
/// exist once (`ProjectPicker.model`).
struct ProjectChoiceSheet: View {
    let picker: (String) -> ProjectPickerModel
    let current: NoteID?
    /// Whether `Clear project` is offered — by default when a project is chosen; the inbox card
    /// also counts a project it is about to create.
    var canClear: Bool?
    let onChoose: (NoteID?) -> Void
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    /// The Mac keyboard walk (#77): on the first row the moment the sheet opens; `nil` while the
    /// search field has the keys.
    @State private var walk: KeyWalk? = KeyWalk.initial
    @FocusState private var hasWalkFocus: Bool
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form
                    .onChange(of: walk) { _, walk in
                        guard let stop = walk?.stop(in: rows) else { return }
                        proxy.scrollTo(stop)
                    }
            }
            .sheetFormStyle()
            .navigationTitle(Copy.project)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) {
                        dismiss()
                        onCancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if walk != nil {
                    KeyWalkLegendLine(press: Copy.walkChoose, hasNextRow: false)
                }
            }
            .keyWalkKeys(
                focus: $hasWalkFocus,
                onMove: { walk = (walk ?? KeyWalk()).moved(by: $0, in: rows.map(\.count)) },
                onPress: press)
            // Typing while the walk has the keys searches: the field takes them over.
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { key in
                guard KeyWalk.isAvailable, !isSearchFocused, !key.modifiers.contains(.command)
                else { return .ignored }
                search += key.characters
                isSearchFocused = true
                return .handled
            }
            .onChange(of: isSearchFocused) { _, focused in
                if focused { walk = nil }
            }
            .onChange(of: search) { _, _ in
                walk = walk.flatMap { _ in KeyWalk.first(in: rows.map(\.count)) }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField(InboxCopy.pickProject, text: $search, prompt: Text(InboxCopy.pickProject))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($isSearchFocused)
                    // `↩` in the search field hands the keys to the walk, on the first match.
                    .onSubmit { handToWalk() }
            }
            if showsClear {
                Section {
                    Button(InboxCopy.clearProject) { choose(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                        .keyHighlight(isHighlighted(.clear), in: Self.rowShape)
                        .id(ProjectPickStop.clear)
                }
            }
            ForEach(pickerModel.groups) { group in
                if let title = group.title {
                    Section(title) { rowViews(of: group) }
                } else {
                    Section { rowViews(of: group) }
                }
            }
            if let name = pickerModel.createTitle {
                Section {
                    Button {
                        create(name)
                    } label: {
                        Label(InboxCopy.createProject(name), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.gtdAccent)
                    .keyHighlight(isHighlighted(.create(name)), in: Self.rowShape)
                    .id(ProjectPickStop.create(name))
                }
            }
        }
    }

    static let rowShape = RoundedRectangle(cornerRadius: 6)

    private var pickerModel: ProjectPickerModel { picker(search) }
    private var showsClear: Bool { canClear ?? (current != nil) }
    private var rows: [[ProjectPickStop]] { pickerModel.walkRows(canClear: showsClear) }

    private func isHighlighted(_ stop: ProjectPickStop) -> Bool {
        walk?.stop(in: rows) == stop
    }

    private func rowViews(of group: ProjectGroup) -> some View {
        ForEach(group.projects) { project in
            Button {
                choose(project.id)
            } label: {
                HStack {
                    Text(project.title).font(Typo.body).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if current == project.id {
                        Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyHighlight(isHighlighted(.project(project.id)), in: Self.rowShape)
            .id(ProjectPickStop.project(project.id))
        }
    }

    private func handToWalk() {
        isSearchFocused = false
        guard KeyWalk.isAvailable else { return }
        walk = KeyWalk.first(in: rows.map(\.count)) ?? KeyWalk()
        hasWalkFocus = true
    }

    /// `↩` does what a click on the highlighted row does.
    private func press() {
        switch walk?.stop(in: rows) {
        case .clear: choose(nil)
        case let .project(id): choose(id)
        case let .create(name): create(name)
        case nil: walk = KeyWalk.first(in: rows.map(\.count))
        }
    }

    private func create(_ name: String) {
        onCreate(name)
        dismiss()
    }

    private func choose(_ id: NoteID?) {
        onChoose(id)
        dismiss()
    }
}
#endif
