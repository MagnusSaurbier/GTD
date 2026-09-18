#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// Projects list (E4). **Owned by T22** — this is the compiling shell.
public struct ProjectsListView: View {
    private let onOpenProject: (NoteID) -> Void
    private let onOpenAction: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(onOpenProject: @escaping (NoteID) -> Void, onOpenAction: @escaping (NoteID) -> Void) {
        self.onOpenProject = onOpenProject
        self.onOpenAction = onOpenAction
    }

    public var body: some View {
        let list = ProjectsListModel(model: model)
        List {
            ForEach(Array(list.sections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section.rows, id: \.project.id) { row in
                        ProjectRow(row: row, today: list.today, onOpenAction: onOpenAction)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenProject(row.project.id) }
                    }
                } header: {
                    if let area = section.area { Text(area.title) }
                }
            }
        }
        .navigationTitle(Copy.project)
    }
}

/// Project detail (P6). **Owned by T22.**
public struct ProjectDetailView: View {
    private let project: NoteID
    private let onOpenAction: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(project: NoteID, onOpenAction: @escaping (NoteID) -> Void) {
        self.project = project
        self.onOpenAction = onOpenAction
    }

    public var body: some View {
        Group {
            if let project = model.snapshot.project(project) {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(project.outcome).font(Typo.sectionHeader)
                    Text(project.why).font(Typo.body).foregroundStyle(Color.textSecondary)
                }
                .padding(Spacing.screenMargin)
                .navigationTitle(project.title)
            } else {
                ContentUnavailableView(Copy.project, systemImage: Symbols.projects)
            }
        }
    }
}

/// `What's next for <project>?` (P5) — presented by the app shell on the `whatsNext` prompt.
public struct WhatsNextSheet: View {
    private let project: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public init(project: NoteID) {
        self.project = project
    }

    public var body: some View {
        let title = model.snapshot.project(project)?.title ?? ""
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.whatsNext(project: title)).font(Typo.sectionHeader)
            ForEach(Array((model.snapshot.project(project)?.openSteps ?? []).enumerated()), id: \.offset) { _, step in
                Text(step.text).font(Typo.body)
            }
            Button(Copy.done) { dismiss() }
        }
        .padding(Spacing.cardPadding)
    }
}

/// A2 — turn an action with two or more checkboxes into a project.
public struct ConvertToProjectSheet: View {
    private let action: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    public init(action: NoteID) {
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.turnIntoProject).font(Typo.sectionHeader)
            ForEach(Array((model.snapshot.action(action)?.checkboxes ?? []).enumerated()), id: \.offset) { _, box in
                Text(box.text).font(Typo.body)
            }
            Button(Copy.done) { dismiss() }
        }
        .padding(Spacing.cardPadding)
    }
}

/// Reusable project picker (used by the inbox card and the action detail view).
public struct ProjectPicker: View {
    @Binding private var selection: NoteID?
    @Environment(AppModel.self) private var model

    public init(selection: Binding<NoteID?>) {
        self._selection = selection
    }

    public var body: some View {
        List(model.snapshot.projects.filter { $0.status == .active }, id: \.id) { project in
            Button {
                selection = selection == project.id ? nil : project.id
            } label: {
                HStack {
                    Text(project.title).font(Typo.body)
                    Spacer()
                    if selection == project.id {
                        Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        ProjectsListView(onOpenProject: { _ in }, onOpenAction: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}
#endif
