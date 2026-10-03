#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox
import GTDFixtures

// MARK: - Projects list (E4)

/// Projects list as a folder tree (#67: area-less projects flat on top, then area folders like
/// the VS Code explorer), with status filters and area/project creation.
/// **Owned by T22.**
///
/// On the Mac the list is a stock selectable `List` (M2, same as `FeatureOverview.ActionListView`):
/// a click or the arrow keys select a row, selecting opens the project in the detail column
/// (`onOpenProject`), and `selection` — the project that column shows — is what the list
/// highlights. The list keeps no selection of its own. iOS keeps tap-to-open.
/// One project row as a drop target for a dragged action (E3): attaches the action to this
/// project, replacing the one it named before.
private struct ProjectDropRow<Content: View>: View {
    let project: NoteID
    @ViewBuilder let content: () -> Content

    var body: some View {
        NoteDropRow(destination: .project(project), content: content)
    }
}

public struct ProjectsListView: View {
    private let selection: NoteID?
    private let onOpenProject: (NoteID) -> Void
    private let onOpenAction: (NoteID) -> Void
    @Environment(AppModel.self) private var model
    @State private var listModel: ProjectsListModel?
    @State private var isPresentingNewProject = false
    /// Folders of the tree the user folded on this device (#67) — `ProjectTreePath.encode`'s
    /// one-path-per-line string. Device state only, never written to the vault.
    @AppStorage("projects.collapsedFolders") private var collapsedFoldersStorage = ""

    public init(
        selection: NoteID? = nil,
        onOpenProject: @escaping (NoteID) -> Void,
        onOpenAction: @escaping (NoteID) -> Void
    ) {
        self.selection = selection
        self.onOpenProject = onOpenProject
        self.onOpenAction = onOpenAction
    }

    public var body: some View {
        let list = listModel ?? ProjectsListModel(model: model)
        Group {
            if list.tree.isEmpty {
                ContentUnavailableView(Copy.projects, systemImage: Symbols.projects)
            } else {
                selectableList {
                    // #67 — one flat `ForEach` over the visible tree lines (area-less projects
                    // first, then folders like the VS Code explorer), so the Mac `List`'s
                    // selection and arrow keys keep working on project rows; folder rows carry
                    // no tag and are not selectable.
                    ForEach(list.lines(collapsed: collapsedFolders)) { line in
                        switch line {
                        case let .folder(id, name, depth, isExpanded):
                            ProjectFolderRow(name: name, depth: depth, isExpanded: isExpanded) {
                                toggleFolder(id)
                            }
                        case let .project(row, id, depth):
                            // A dragged action dropped here is attached to this project
                            // (E3); it replaces the project the action named before.
                            ProjectDropRow(project: id) {
                                ProjectRow(row: row, today: list.today, onOpenAction: onOpenAction)
                                    .padding(.leading, ProjectFolderRow.indent(depth))
                                    .contentShape(Rectangle())
                                    #if !os(macOS)
                                    .onTapGesture { onOpenProject(id) }
                                    #endif
                            }
                            .tag(id)
                        }
                    }
                }
            }
        }
    .safeAreaInset(edge: .top) { StatusFilterBar(listModel: list) }
        .navigationTitle(Copy.projects)
        .toolbar {
            ToolbarItem {
                Button {
                    isPresentingNewProject = true
                } label: {
                    Label(Copy.project, systemImage: Symbols.capture)
                }
            }
        }
        .sheet(isPresented: $isPresentingNewProject) {
            NewProjectSheet(listModel: list)
        }
        .task { if listModel == nil { listModel = list } }
    }

    private var collapsedFolders: Set<String> { ProjectTreePath.decode(collapsedFoldersStorage) }

    /// Instant, like the Knowledge tree (#24) — no disclosure animation.
    private func toggleFolder(_ id: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            collapsedFoldersStorage = ProjectTreePath.encode(
                ProjectTreePath.toggling(id, in: collapsedFolders))
        }
    }

    /// macOS: `List(selection:)` — highlight, arrow keys and accessibility selection for free.
    /// iOS has no persistent row selection outside edit mode, so rows stay tap-to-open there.
    @ViewBuilder
    private func selectableList<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        #if os(macOS)
        List(selection: Binding<NoteID?>(
            get: { selection },
            set: { if let id = $0 { onOpenProject(id) } }),
            content: rows)
        #else
        List(content: rows)
        #endif
    }
}

/// A folder node of the projects tree (#67): chevron, folder icon, name — the look of the
/// Knowledge sheet's own tree rows (#24). The whole row toggles the folder, as in VS Code.
private struct ProjectFolderRow: View {
    let name: String
    let depth: Int
    let isExpanded: Bool
    let toggle: () -> Void

    /// Leading inset of a row at `depth`: one chevron slot per level. A project inside a folder
    /// lines up with its folder's icon.
    static func indent(_ depth: Int) -> CGFloat {
        depth > 0 ? CGFloat(depth) * Spacing.l + Spacing.xs : 0
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isExpanded ? Symbols.collapse : Symbols.nextMonth)
                    .font(Typo.controlGlyph)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Spacing.l, height: Spacing.l)
                Label(name, systemImage: Symbols.area)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isExpanded ? ProjectsCopy.folderExpanded : ProjectsCopy.folderCollapsed)
        .accessibilityHint(isExpanded ? ProjectsCopy.collapseFolder : ProjectsCopy.expandFolder)
    }
}

/// Multi-select status filters (E4 "Sections/filters"), same `Chip` component as everywhere else.
private struct StatusFilterBar: View {
    let listModel: ProjectsListModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.chipGap) {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Chip(
                        Copy.projectStatus(status),
                        state: listModel.statuses.contains(status) ? .confirmed : .unset
                    ) {
                        listModel.toggleStatus(status)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.s)
        }
    }
}

/// Minimal creation form (E4 "Create area / project"). Undecided fields stay empty — outcome and
/// why are optional at creation and editable afterwards from `ProjectDetailView`.
private struct NewProjectSheet: View {
    let listModel: ProjectsListModel
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var newAreaTitle = ""
    @State private var selectedArea: NoteID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.project).font(Typo.sectionHeader)

            TextField("Project title", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.body)

            Text(Copy.area).font(Typo.meta).foregroundStyle(Color.textSecondary)
            FlowLayout {
                ForEach(model.snapshot.areas, id: \.id) { area in
                    Chip(area.title, state: selectedArea == area.id ? .confirmed : .unset) {
                        selectedArea = selectedArea == area.id ? nil : area.id
                        if selectedArea != nil { newAreaTitle = "" }
                    }
                }
            }
            TextField("New area", text: $newAreaTitle)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .disabled(selectedArea != nil)

            if let errorMessage {
                Text(errorMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }

            HStack {
                Spacer()
                Button(Copy.done) { Task { await create() } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.cardPadding)
    }

    private func create() async {
        let draft = ProjectDraft(
            title: title,
            area: selectedArea,
            newAreaTitle: newAreaTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newAreaTitle)
        do {
            try await listModel.createProject(draft)
            dismiss()
        } catch {
            errorMessage = "\(error)"
        }
    }
}

// MARK: - Project detail (P6)

/// Mac-first project view, usable on iPhone: header, status, one list of steps and the
/// project's active actions (#76), reference files, dated log. **Owned by T22.**
public struct ProjectDetailView: View {
    private let projectID: NoteID
    private let onOpenAction: (NoteID) -> Void
    private let onOpenProject: ((NoteID) -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.vaultRootPath) private var vaultRootPath
    @State private var detailModel: ProjectDetailModel?
    @State private var newStepText = ""
    /// The suggestion row `↓`/`↑` has moved to; Return links it instead of adding plain text.
    @State private var highlightedSuggestion: Int?
    @State private var cardRequest: CardRequest?
    @State private var demotionNotice: String?

    /// `onOpenProject` opens a subproject a step points at (`→ Project`); without it those rows
    /// only show where the step stands.
    public init(
        project: NoteID,
        onOpenAction: @escaping (NoteID) -> Void,
        onOpenProject: ((NoteID) -> Void)? = nil
    ) {
        self.projectID = project
        self.onOpenAction = onOpenAction
        self.onOpenProject = onOpenProject
    }

    /// The action card a row's badge opens (#74, #76).
    private enum CardRequest: Identifiable, Hashable {
        /// `↗ Promote` on an open step.
        case promote(stepIndex: Int)
        /// `→ Next` etc. on a step's action or a loose action: change where it stands.
        case status(NoteID)

        var id: Self { self }
    }

    public var body: some View {
        // The Mac detail column keeps this view (and its state) when the sidebar hands it
        // another project, so a cached model bound to a different project is dropped.
        let detail = detailModel.flatMap { $0.projectID == projectID ? $0 : nil }
            ?? ProjectDetailModel(project: projectID, model: model)
        Group {
            if let project = detail.project {
                // Stock `List` throughout (STYLEGUIDE §1.5) — the steps section needs one for
                // `.onMove` (drag reorder) to work at all.
                List {
                    Section {
                        header(project, detail)
                        statusSection(project, detail)
                    }
                    Section("Steps") {
                        stepsSection(detail)
                    }
                    if !detail.referenceFiles.isEmpty {
                        Section(Copy.knowledge) {
                            referenceFilesSection(detail)
                        }
                    }
                    if !detail.log.isEmpty {
                        Section("Log") {
                            logSection(detail)
                        }
                    }
                    Section {
                        NoteFileLinks(note: project.id)
                    }
                }
                .navigationTitle(project.title)
            } else {
                ContentUnavailableView(Copy.project, systemImage: Symbols.projects)
            }
        }
        .task(id: projectID) {
            guard detailModel?.projectID != projectID else { return }
            detailModel = detail
            newStepText = ""
            highlightedSuggestion = nil
            cardRequest = nil
            demotionNotice = nil
        }
        .sheet(item: $cardRequest) { request in
            switch request {
            case let .promote(stepIndex):
                PromoteStepSheet(model: model, detailModel: detail, stepIndex: stepIndex)
            case let .status(id):
                if let action = model.snapshot.action(id) {
                    ChangeStatusSheet(model: model, action: action)
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ project: Project, _ detail: ProjectDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            TextField("Done when…", text: outcomeBinding(detail), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.screenTitle)

            Text(Copy.why).font(Typo.sectionHeader)
            NoteEditor(text: whyBinding(detail), prompt: Copy.whyPlaceholder, tone: .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(Copy.area).font(Typo.meta).foregroundStyle(Color.textSecondary)
            AreaPicker(detail: detail)
        }
    }

    private func outcomeBinding(_ detail: ProjectDetailModel) -> Binding<String> {
        Binding(
            get: { detail.project?.outcome ?? "" },
            set: { text in Task { try? await detail.setOutcome(text) } })
    }

    private func whyBinding(_ detail: ProjectDetailModel) -> Binding<String> {
        Binding(
            get: { detail.project?.why ?? "" },
            set: { text in Task { try? await detail.setWhy(text) } })
    }

    @ViewBuilder
    private func statusSection(_ project: Project, _ detail: ProjectDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FlowLayout {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Chip(Copy.projectStatus(status), state: project.status == status ? .confirmed : .unset) {
                        Task {
                            let count = try? await detail.setStatus(status)
                            demotionNotice = (count ?? 0) > 0
                                ? "\(count ?? 0) \(Copy.next) → \(Copy.someday)"
                                : nil
                        }
                    }
                }
            }
            if let demotionNotice {
                Text(demotionNotice).font(Typo.counter).foregroundStyle(Color.textSecondary)
            }
            if detail.isStalled {
                Text(Copy.stalledProjectBody).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func stepsSection(_ detail: ProjectDetailModel) -> some View {
        // Row IDs are namespaced per section: steps and log both enumerate from 0 inside one
        // `List`, and bare offsets let the Mac table hand a log row to step 0 (#48).
        ForEach(Array(detail.steps.enumerated()), id: \.offset.stepRowID) { index, step in
            StepRow(
                step: step,
                standing: detail.standing(of: step),
                onToggle: { Task { try? await detail.toggleStep(at: index) } },
                onEdit: { text in Task { try? await detail.editStep(at: index, text: text) } },
                onMoveUp: { Task { try? await detail.moveStepUp(at: index) } },
                onMoveDown: { Task { try? await detail.moveStepDown(at: index) } },
                onDelete: { Task { try? await detail.deleteStep(at: index) } },
                onPromote: { cardRequest = .promote(stepIndex: index) },
                onChangeStatus: { cardRequest = .status($0) },
                onOpen: openHandler(for: step))
        }
        .onMove { offsets, destination in
            Task { try? await detail.moveStep(fromOffsets: offsets, toOffset: destination) }
        }

        // #76 — the project's actions no step points at (older notes; new ones get a step by
        // themselves), laid out like a step row, same badge.
        ForEach(detail.looseActions, id: \.id) { action in
            HStack(spacing: Spacing.m) {
                Image(systemName: "circle")
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenAction(action.id) }
                    .accessibilityAddTraits(.isButton)
                StepStandingBadge(.action(action)) { cardRequest = .status(action.id) }
            }
        }

        // #61 — typing offers existing actions; picking one links it instead of adding text.
        let suggestions = detail.linkSuggestions(for: newStepText)
        TextField("New step", text: $newStepText)
            .textFieldStyle(.plain)
            .font(Typo.body)
            .onChange(of: newStepText) { highlightedSuggestion = nil }
            .onKeyPress(.downArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                highlightedSuggestion = min((highlightedSuggestion ?? -1) + 1, suggestions.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard let current = highlightedSuggestion else { return .ignored }
                highlightedSuggestion = current == 0 ? nil : current - 1
                return .handled
            }
            .onKeyPress(.escape) {
                guard highlightedSuggestion != nil else { return .ignored }
                highlightedSuggestion = nil
                return .handled
            }
            .onSubmit {
                if let index = highlightedSuggestion, suggestions.indices.contains(index) {
                    link(suggestions[index], detail)
                } else {
                    Task {
                        try? await detail.addStep(newStepText)
                        newStepText = ""
                    }
                }
            }

        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, action in
            StepLinkSuggestionRow(action: action, isHighlighted: index == highlightedSuggestion) {
                link(action, detail)
            }
        }
    }

    private func link(_ action: Action, _ detail: ProjectDetailModel) {
        newStepText = ""
        highlightedSuggestion = nil
        Task { await model.report { try await detail.linkStep(to: action.id) } }
    }

    /// A click on the row opens the note the step points at: its action, or a subproject when
    /// the shell can show one. A plain step has no note — its text stays editable instead.
    private func openHandler(for step: ProjectStep) -> (() -> Void)? {
        guard let target = step.promotedTo else { return nil }
        if model.snapshot.action(target) != nil { return { onOpenAction(target) } }
        if model.snapshot.project(target) != nil, let onOpenProject {
            return { onOpenProject(target) }
        }
        return nil
    }

    @ViewBuilder
    private func referenceFilesSection(_ detail: ProjectDetailModel) -> some View {
        ForEach(detail.referenceFiles, id: \.self) { path in
            if let url = ObsidianLink.url(forVaultPath: path, vaultRoot: vaultRootPath) {
                Link(destination: url) {
                    Label(path, systemImage: Symbols.knowledge)
                }
                .font(Typo.body)
            } else {
                Text(path).font(Typo.body)
            }
        }
    }

    @ViewBuilder
    private func logSection(_ detail: ProjectDetailModel) -> some View {
        ForEach(Array(detail.log.enumerated()), id: \.offset.logRowID) { _, entry in
            HStack(alignment: .top, spacing: Spacing.s) {
                Text(DateText.short(entry.day, today: detail.today))
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                Text(entry.text).font(Typo.body)
            }
        }
    }
}

/// Distinct row IDs for the sections of `ProjectDetailView`'s one `List` (#48).
private extension Int {
    var stepRowID: String { "step-\(self)" }
    var logRowID: String { "log-\(self)" }
}

/// One row of the step list: check, text, where it stands (#76), reorder, delete (P6).
/// A step that points at a note shows its text as a link to it (`onOpen`); a plain step's text
/// is editable.
private struct StepRow: View {
    let step: ProjectStep
    let standing: ProjectDetailModel.StepStanding
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onPromote: () -> Void
    let onChangeStatus: (NoteID) -> Void
    let onOpen: (() -> Void)?

    /// What the user is typing, only while they edit this row. Otherwise the row shows
    /// `step.text` straight from the model: the Mac `List` reuses row views, and a copy taken
    /// at init could show — and on blur write back — another step's text (#48, #62).
    @State private var draft: String?
    @FocusState private var isFocused: Bool

    init(
        step: ProjectStep,
        standing: ProjectDetailModel.StepStanding,
        onToggle: @escaping () -> Void,
        onEdit: @escaping (String) -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onPromote: @escaping () -> Void,
        onChangeStatus: @escaping (NoteID) -> Void,
        onOpen: (() -> Void)?
    ) {
        self.step = step
        self.standing = standing
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onDelete = onDelete
        self.onPromote = onPromote
        self.onChangeStatus = onChangeStatus
        self.onOpen = onOpen
    }

    private var text: Binding<String> {
        Binding(get: { draft ?? step.text }, set: { draft = $0 })
    }

    /// Hands a changed draft to the model and drops it, so the row follows the note again.
    private func commit() {
        if let draft, draft != step.text { onEdit(draft) }
        draft = nil
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: step.done ? Symbols.done : "circle")
                    .foregroundStyle(step.done ? Color.gtdAccent : Color.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(step.promotedTo != nil)

            if let onOpen {
                Text(step.text)
                    .font(Typo.body)
                    .strikethrough(step.done)
                    .foregroundStyle(step.done ? Color.textSecondary : Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
                    .accessibilityAddTraits(.isButton)
            } else {
                TextField("Step", text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .strikethrough(step.done)
                    .foregroundStyle(step.done ? Color.textSecondary : Color.ink)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
            }

            switch standing {
            case .promotable:
                StepStandingBadge(.promotable, action: onPromote)
            case let .action(action):
                StepStandingBadge(.action(action)) { onChangeStatus(action.id) }
            case .project:
                if let onOpen { StepStandingBadge(standing, action: onOpen) }
                else { StepStandingBadge(standing, action: nil) }
            case .settled:
                EmptyView()
            }

            // Reorder: drag via `.onMove` (List's native handle) on every platform, plus `⌥↑↓`
            // on Mac once this row's text field is focused (P6). STYLEGUIDE §7's icon map has no
            // "move up/down" concept, so `Symbols.moveUp`/`moveDown` are the closest stock
            // chevrons, named in DesignSystem rather than written into feature code (§9).
            VStack(spacing: 0) {
                Button(action: onMoveUp) { Image(systemName: Symbols.moveUp) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Move step up")
                    .modifier(OptionArrowShortcut(isActive: isFocused, key: .upArrow))
                Button(action: onMoveDown) { Image(systemName: Symbols.moveDown) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Move step down")
                    .modifier(OptionArrowShortcut(isActive: isFocused, key: .downArrow))
            }
            .foregroundStyle(Color.textTertiary)
            .font(Typo.controlGlyph)

            Button(action: onDelete) {
                Image(systemName: Symbols.trash)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textTertiary)
            .accessibilityLabel("Delete step")
        }
    }
}

/// The badge on the right of a step-list row (#76): `↗ Promote` on an open step, `→ Next` /
/// `→ Someday` / `→ Waiting` for an action, `→ Project` for a subproject. One style for all,
/// the neutral `Badge`; a button whenever it has something to open.
private struct StepStandingBadge: View {
    let standing: ProjectDetailModel.StepStanding
    let action: (() -> Void)?

    init(_ standing: ProjectDetailModel.StepStanding, action: (() -> Void)?) {
        self.standing = standing
        self.action = action
    }

    var body: some View {
        if let content {
            if let action {
                Button(action: action) { Badge(content) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(content.accessibilityLabel)
            } else {
                Badge(content)
            }
        }
    }

    private var content: BadgeContent? {
        switch standing {
        case .promotable:
            BadgeContent(
                text: Copy.promote, symbol: Symbols.promoteStep, step: .neutral,
                accessibilityLabel: Copy.promote)
        case let .action(action):
            BadgeContent(
                text: Copy.status(action.status), symbol: Symbols.stepStatus, step: .neutral,
                accessibilityLabel: "\(Copy.status(action.status)), change status")
        case .project:
            BadgeContent(
                text: Copy.project, symbol: Symbols.stepStatus, step: .neutral,
                accessibilityLabel: "Subproject")
        case .settled:
            nil
        }
    }
}

/// `→ Next` etc. (#76): the inbox's action card over an existing action, to change its status.
private struct ChangeStatusSheet: View {
    private let makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, action: Action) {
        makeAction = MakeActionModel(model: model, changingStatusOf: action)
    }

    var body: some View {
        ProjectActionCard(makeAction) { _ in dismiss() }
    }
}

/// One existing action the "New step" field offers (#61). Tapping it links the action as a step.
private struct StepLinkSuggestionRow: View {
    let action: Action
    let isHighlighted: Bool
    let onLink: () -> Void

    var body: some View {
        Button(action: onLink) {
            HStack(spacing: Spacing.m) {
                Image(systemName: Symbols.linkStep)
                    .foregroundStyle(Color.textTertiary)
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.s)
                Text(Copy.status(action.status))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isHighlighted ? Color.accentWash : nil)
        .accessibilityLabel(Copy.linkAsStep(action.title))
    }
}

/// Attaches `⌥` + `key` only while `isActive` (the row's text field is focused), so a whole
/// checklist of rows never registers the same shortcut more than once at a time.
private struct OptionArrowShortcut: ViewModifier {
    let isActive: Bool
    let key: KeyEquivalent

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.keyboardShortcut(key, modifiers: .option)
        } else {
            content
        }
    }
}

/// The inbox's opened action card (STYLEGUIDE §3.5 step 2a) over one `MakeActionModel`, for
/// every sheet in this target that turns a step or a typed line into an action (#74). The
/// fields, asterisks, cap sheet and exits are the inbox's own, so a change to the card reaches
/// these sheets without a copy here. `onFinished(true)` once filed, `(false)` on cancel.
private struct ProjectActionCard: View {
    @State private var makeAction: MakeActionModel
    @Environment(\.keyBindings) private var keyBindings
    private let onFinished: (Bool) -> Void

    init(_ makeAction: MakeActionModel, onFinished: @escaping (Bool) -> Void) {
        _makeAction = State(initialValue: makeAction)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            MakeActionCardView(model: makeAction) { onFinished(makeAction.isFiled) }
        }
        .onChange(of: keyBindings, initial: true) { _, bindings in
            makeAction.keyBindings = bindings
        }
    }
}

/// Promotion from the project detail (P6): the card over the step.
private struct PromoteStepSheet: View {
    private let makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, detailModel: ProjectDetailModel, stepIndex: Int) {
        let text = detailModel.steps.indices.contains(stepIndex)
            ? detailModel.steps[stepIndex].text : ""
        makeAction = MakeActionModel(
            model: model, project: detailModel.projectID, stepIndex: stepIndex, stepText: text)
    }

    var body: some View {
        ProjectActionCard(makeAction) { _ in dismiss() }
    }
}

// MARK: - What's next? (P5)

/// Presented by the app shell on the `whatsNext` prompt after completing a project action.
/// Choosing a step, or typing a new action, opens the inbox's action card in place (#74);
/// cancelling the card comes back here. **Owned by T22.**
public struct WhatsNextSheet: View {
    private let projectID: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var whatsNextModel: WhatsNextModel?
    @State private var freeText = ""
    /// The Someday row `↓`/`↑` has moved to; Return opens it instead of the typed line.
    @State private var highlightedSomeday: Int?
    @State private var card: MakeActionModel?

    public init(project: NoteID) {
        self.projectID = project
    }

    public var body: some View {
        if let card {
            ProjectActionCard(card) { filed in
                if filed { dismiss() } else { self.card = nil }
            }
        } else {
            chooser
        }
    }

    private var chooser: some View {
        let next = whatsNextModel ?? WhatsNextModel(project: projectID, model: model)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.whatsNext(project: next.title)).font(Typo.sectionHeader)

            // A long project's open steps scroll instead of pushing the buttons off the sheet.
            if !next.openSteps.isEmpty {
                OverflowScroll {
                    ForEach(next.openSteps) { entry in
                        Button {
                            card = MakeActionModel(
                                model: model, project: projectID,
                                stepIndex: entry.stepIndex, stepText: entry.step.text)
                        } label: {
                            Text(entry.step.text).font(Typo.body)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // #84 — the project's Someday pile, narrowed as the user types; picking one opens
            // the card over that note instead of writing a new one.
            let someday = next.somedaySuggestions(for: freeText)
            HStack {
                TextField("New action", text: $freeText)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .onChange(of: freeText) { highlightedSomeday = nil }
                    .onKeyPress(.downArrow) {
                        guard !someday.isEmpty else { return .ignored }
                        highlightedSomeday = min((highlightedSomeday ?? -1) + 1, someday.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard let current = highlightedSomeday else { return .ignored }
                        highlightedSomeday = current == 0 ? nil : current - 1
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard highlightedSomeday != nil else { return .ignored }
                        highlightedSomeday = nil
                        return .handled
                    }
                    .onSubmit {
                        if let index = highlightedSomeday, someday.indices.contains(index) {
                            open(someday[index])
                        } else {
                            openFreeText()
                        }
                    }
                Button(Copy.done, action: openFreeText)
                    .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !someday.isEmpty {
                Text(Copy.someday).font(Typo.meta).foregroundStyle(Color.textSecondary)
                OverflowScroll {
                    ForEach(Array(someday.enumerated()), id: \.element.id) { index, action in
                        SomedaySuggestionRow(action: action, isHighlighted: index == highlightedSomeday) {
                            open(action)
                        }
                    }
                }
            }

            if next.isStalled {
                Text(Copy.stalledProjectBody).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }

            HStack {
                Button("Nothing yet") { dismiss() }
                Spacer()
                Button("Project is done") { Task { try? await next.markDone(); dismiss() } }
                Spacer()
                Button(Copy.done) { dismiss() }
            }
        }
        .padding(Spacing.cardPadding)
        .task { if whatsNextModel == nil { whatsNextModel = next } }
    }

    private func openFreeText() {
        let title = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        card = MakeActionModel(model: model, project: projectID, newActionTitle: title)
    }

    private func open(_ action: Action) {
        highlightedSomeday = nil
        card = MakeActionModel(model: model, changingStatusOf: action)
    }
}

/// One of the project's Someday actions under What's next?'s field (#84).
private struct SomedaySuggestionRow: View {
    let action: Action
    let isHighlighted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.m) {
                Image(systemName: Symbols.someday)
                    .foregroundStyle(Color.textTertiary)
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.s)
            .background(isHighlighted ? Color.accentWash : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.cell))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Turn into project (A2)

/// Opened from the inline "Turn into project" button (T20 card, T25 detail): an action's
/// checkboxes become steps, title/why carry over, first step starts pre-selected for promotion.
/// `Done` converts; a selected step then opens the inbox's action card over that step of the
/// new project (#74). Cancelling the card leaves the project with the step still open.
/// **Owned by T22.**
public struct ConvertToProjectSheet: View {
    private let actionID: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var convertModel: ConvertToProjectModel?
    @State private var title = ""
    @State private var steps: [String] = []
    @State private var selectedStepIndex: Int? = 0
    @State private var errorMessage: String?
    @State private var didSeed = false
    @State private var card: MakeActionModel?

    public init(action: NoteID) {
        self.actionID = action
    }

    public var body: some View {
        if let card {
            ProjectActionCard(card) { _ in dismiss() }
        } else {
            form
        }
    }

    private var form: some View {
        let convert = convertModel ?? ConvertToProjectModel(action: actionID, model: model)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.turnIntoProject).font(Typo.sectionHeader)

            TextField("Project title", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.screenTitle)

            if !steps.isEmpty {
                OverflowScroll {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: Spacing.m) {
                            Image(systemName: selectedStepIndex == index ? Symbols.done : "circle")
                                .foregroundStyle(selectedStepIndex == index ? Color.gtdAccent : Color.textTertiary)
                                .onTapGesture { selectedStepIndex = selectedStepIndex == index ? nil : index }
                            Text(step).font(Typo.body)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }

            HStack {
                Spacer()
                Button(Copy.done) { Task { await convertNow(convert) } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.cardPadding)
        .task {
            if convertModel == nil { convertModel = convert }
            if !didSeed {
                didSeed = true
                let draft = convert.makeDraft()
                title = draft.title
                steps = draft.steps
                selectedStepIndex = draft.steps.isEmpty ? nil : 0
            }
        }
    }

    private func convertNow(_ convert: ConvertToProjectModel) async {
        let draft = ProjectDraft(title: title, why: convert.action?.why ?? "", steps: steps)
        do {
            try await convert.convert(draft, promoteStepIndex: nil)
        } catch {
            errorMessage = "\(error)"
            return
        }
        guard let index = selectedStepIndex, draft.steps.indices.contains(index) else {
            dismiss()
            return
        }
        card = MakeActionModel(
            model: model, project: convert.projectID(for: draft),
            stepIndex: index, stepText: draft.steps[index])
    }
}

// MARK: - Project picker (reused by inbox card and action detail)

/// Reusable project picker (action detail, deferred sweep): a **chip** showing the current
/// project (confirmed) or an unset `Project` chip with the `plus` symbol; tapping it opens the
/// list — popover on Mac, medium sheet on iOS, the same presentation as `DateValueChip`.
///
/// It used to be a bare `List`, which collapses to zero height inside a `ScrollView` — the action
/// detail showed the "Project" label with nothing under it (walkthrough 2026-09-19, P6). What the
/// chip and the list show is decided in `ProjectPickerContent`.
public struct ProjectPicker: View {
    @Binding private var selection: NoteID?
    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    public init(selection: Binding<NoteID?>) {
        self._selection = selection
    }

    public var body: some View {
        let chip = ProjectPickerContent.chip(selection: selection, in: model.snapshot)
        Chip(chip.title, state: chip.state, symbol: chip.state == .unset ? Symbols.addValue : nil) {
            isPresented = true
        }
        .accessibilityLabel(Copy.spoken(chip.state == .unset ? [chip.title] : [Copy.project, chip.title]))
        .popover(isPresented: $isPresented) { list }
    }

    private var list: some View {
        List(ProjectPickerContent.options(selection: selection, in: model.snapshot), id: \.id) { project in
            Button {
                selection = ProjectPickerContent.toggled(project.id, from: selection)
                isPresented = false
            } label: {
                HStack {
                    Text(project.title).font(Typo.body).foregroundStyle(Color.ink)
                    Spacer()
                    if selection == project.id {
                        Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == project.id ? [.isSelected] : [])
        }
        .frame(minWidth: 280, minHeight: 320)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

// MARK: - Area picker (P6, R-7)

/// The project detail's area picker: a **chip** showing the current area (confirmed) or an
/// unset `Area` chip; tapping it opens the list of areas — popover on Mac, medium sheet on iOS,
/// the same presentation as `ProjectPicker`/`DateValueChip`. Never a "No area" row inside that
/// list (STYLEGUIDE); clearing the area is the separate `ProjectsCopy.removeFromArea` action,
/// offered only once the project has an area to remove.
///
/// `ProjectDetailModel.setArea(_:)` can refuse (`GTDError.titleCollision`/`.notFound`, R-7) —
/// the refusal is shown inline here, never swallowed with `try?` (ARCHITECTURE §6).
private struct AreaPicker: View {
    let detail: ProjectDetailModel
    @State private var isPresented = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let chip = AreaPickerContent.chip(area: detail.area)
            Chip(chip.title, state: chip.state, symbol: chip.state == .unset ? Symbols.addValue : nil) {
                isPresented = true
            }
            .accessibilityLabel(Copy.spoken(chip.state == .unset ? [chip.title] : [Copy.area, chip.title]))
            .popover(isPresented: $isPresented) { list }
            if let errorMessage {
                Text(errorMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(detail.areas, id: \.id) { area in
                Button {
                    Task { await setArea(area.id) }
                } label: {
                    HStack {
                        Text(area.title).font(Typo.body).foregroundStyle(Color.ink)
                        Spacer()
                        if detail.area?.id == area.id {
                            Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(detail.area?.id == area.id ? [.isSelected] : [])
            }
            if detail.area != nil {
                Button(role: .destructive) {
                    Task { await setArea(nil) }
                } label: {
                    Text(ProjectsCopy.removeFromArea)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 280, minHeight: 320)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func setArea(_ area: NoteID?) async {
        do {
            try await detail.setArea(area)
            errorMessage = nil
            isPresented = false
        } catch {
            errorMessage = AreaPickerContent.message(for: error)
        }
    }
}

#Preview("List") {
    NavigationStack {
        ProjectsListView(onOpenProject: { _ in }, onOpenAction: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Detail") {
    NavigationStack {
        ProjectDetailView(project: Fixtures.daadProject.id, onOpenAction: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Detail — stalled") {
    NavigationStack {
        ProjectDetailView(project: Fixtures.flatProject.id, onOpenAction: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("What's next") {
    WhatsNextSheet(project: Fixtures.daadProject.id)
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}

#Preview("Turn into project") {
    ConvertToProjectSheet(action: Fixtures.sampleSnapshot.actions.first { $0.checkboxes.count >= 2 }?.id
        ?? Fixtures.sampleSnapshot.actions[0].id)
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
