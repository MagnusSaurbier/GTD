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
                    })
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
                case let .deferDate(action):
                    DeferDateSheet(initial: action.deferDate, today: coordinator.today) { date in
                        Task { await coordinator.confirmDefer(action, date: date) }
                    }
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
    let onChoose: (NoteID?) -> Void
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(InboxCopy.pickProject, text: $search, prompt: Text(InboxCopy.pickProject))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                }
                if current != nil {
                    Section {
                        Button(InboxCopy.clearProject) { choose(nil) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.gtdAccent)
                    }
                }
                ForEach(pickerModel.groups) { group in
                    if let title = group.title {
                        Section(title) { rows(of: group) }
                    } else {
                        Section { rows(of: group) }
                    }
                }
                if let name = pickerModel.createTitle {
                    Section {
                        Button {
                            onCreate(name)
                            dismiss()
                        } label: {
                            Label(InboxCopy.createProject(name), systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                    }
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
        }
    }

    private var pickerModel: ProjectPickerModel { picker(search) }

    private func rows(of group: ProjectGroup) -> some View {
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
        }
    }

    private func choose(_ id: NoteID?) {
        onChoose(id)
        dismiss()
    }
}
#endif
