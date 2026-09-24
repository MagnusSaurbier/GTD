#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

// MARK: - Projects list (E4)

/// Projects list, grouped by area, with status filters and area/project creation.
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
            if list.sections.isEmpty {
                ContentUnavailableView(Copy.projects, systemImage: Symbols.projects)
            } else {
                selectableList {
                    ForEach(Array(list.sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.rows, id: \.project.id) { row in
                                // A dragged action dropped here is attached to this project
                                // (E3); it replaces the project the action named before.
                                ProjectDropRow(project: row.project.id) {
                                    ProjectRow(row: row, today: list.today, onOpenAction: onOpenAction)
                                        .contentShape(Rectangle())
                                        #if !os(macOS)
                                        .onTapGesture { onOpenProject(row.project.id) }
                                        #endif
                                }
                                .tag(row.project.id)
                            }
                        } header: {
                            if let area = section.area { Text(area.title) }
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

/// Mac-first project view, usable on iPhone: header, status, step checklist, active actions,
/// reference files, dated log. **Owned by T22.**
public struct ProjectDetailView: View {
    private let projectID: NoteID
    private let onOpenAction: (NoteID) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.vaultRootPath) private var vaultRootPath
    @State private var detailModel: ProjectDetailModel?
    @State private var newStepText = ""
    @State private var promptingStepIndex: Int?
    @State private var demotionNotice: String?

    public init(project: NoteID, onOpenAction: @escaping (NoteID) -> Void) {
        self.projectID = project
        self.onOpenAction = onOpenAction
    }

    public var body: some View {
        let detail = detailModel ?? ProjectDetailModel(project: projectID, model: model)
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
                    if !detail.activeActions.isEmpty {
                        Section(Copy.next) {
                            activeActionsSection(detail)
                        }
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
                }
                .navigationTitle(project.title)
            } else {
                ContentUnavailableView(Copy.project, systemImage: Symbols.projects)
            }
        }
        .task { if detailModel == nil { detailModel = detail } }
        .sheet(item: promptingStepIndexBinding) { identified in
            PromoteStepSheet(detailModel: detail, stepIndex: identified.value)
        }
    }

    /// `.sheet(item:)` needs an `Identifiable`; wraps the plain `Int?` state.
    private var promptingStepIndexBinding: Binding<IdentifiedInt?> {
        Binding(
            get: { promptingStepIndex.map(IdentifiedInt.init) },
            set: { promptingStepIndex = $0?.value })
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
        ForEach(Array(detail.steps.enumerated()), id: \.offset) { index, step in
            StepRow(
                step: step,
                onToggle: { Task { try? await detail.toggleStep(at: index) } },
                onEdit: { text in Task { try? await detail.editStep(at: index, text: text) } },
                onMoveUp: { Task { try? await detail.moveStepUp(at: index) } },
                onMoveDown: { Task { try? await detail.moveStepDown(at: index) } },
                onPromote: step.done || step.promotedTo != nil ? nil : { promptingStepIndex = index })
        }
        .onMove { offsets, destination in
            Task { try? await detail.moveStep(fromOffsets: offsets, toOffset: destination) }
        }

        TextField("New step", text: $newStepText)
            .textFieldStyle(.plain)
            .font(Typo.body)
            .onSubmit {
                Task {
                    try? await detail.addStep(newStepText)
                    newStepText = ""
                }
            }
    }

    @ViewBuilder
    private func activeActionsSection(_ detail: ProjectDetailModel) -> some View {
        ForEach(detail.activeActions, id: \.id) { action in
            ActionRow(action: action)
                .contentShape(Rectangle())
                .onTapGesture { onOpenAction(action.id) }
        }
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
        ForEach(Array(detail.log.enumerated()), id: \.offset) { _, entry in
            HStack(alignment: .top, spacing: Spacing.s) {
                Text(DateText.short(entry.day, today: detail.today))
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                Text(entry.text).font(Typo.body)
            }
        }
    }
}

private struct IdentifiedInt: Identifiable {
    let value: Int
    var id: Int { value }
}

/// One row of the step checklist: check, editable text, reorder, promote (P6).
private struct StepRow: View {
    let step: ProjectStep
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onPromote: (() -> Void)?

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        step: ProjectStep,
        onToggle: @escaping () -> Void,
        onEdit: @escaping (String) -> Void,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onPromote: (() -> Void)?
    ) {
        self.step = step
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onPromote = onPromote
        self._text = State(initialValue: step.text)
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: step.done ? Symbols.done : "circle")
                    .foregroundStyle(step.done ? Color.gtdAccent : Color.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(step.promotedTo != nil)

            TextField("Step", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .strikethrough(step.done)
                .foregroundStyle(step.done ? Color.textSecondary : Color.ink)
                .focused($isFocused)
                .onSubmit { onEdit(text) }
                .onChange(of: isFocused) { _, focused in
                    if !focused { onEdit(text) }
                }

            if step.promotedTo != nil {
                Badge(BadgeContent(
                    text: Copy.promote, symbol: Symbols.promoteStep, step: .neutral,
                    accessibilityLabel: "Promoted to an action"))
            } else if let onPromote {
                Button(action: onPromote) {
                    Image(systemName: Symbols.promoteStep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.promote)
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
        }
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

/// The small action-draft form promotion opens from the project detail (P6): contexts + time
/// chips, status Next or Someday. Cap handling is simplified from T20: a single "Send to
/// Someday instead" retry rather than the full "Next is full" demote sheet.
private struct PromoteStepSheet: View {
    let detailModel: ProjectDetailModel
    let stepIndex: Int
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var contexts: [String] = []
    @State private var timeBucket: TimeBucket?
    @State private var status: ActionStatus = .next
    @State private var capMessage: String?

    init(detailModel: ProjectDetailModel, stepIndex: Int) {
        self.detailModel = detailModel
        self.stepIndex = stepIndex
        _title = State(initialValue: detailModel.steps.indices.contains(stepIndex)
            ? detailModel.steps[stepIndex].text : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.promote).font(Typo.sectionHeader)

            TextField("Action title", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.body)

            ContextChipGroup(contexts: model.snapshot.config.contexts, selection: $contexts)
            TimeBucketChipGroup(selection: $timeBucket)

            HStack(spacing: Spacing.chipGap) {
                Chip(Copy.next, state: status == .next ? .confirmed : .unset) { status = .next }
                Chip(Copy.someday, state: status == .someday ? .confirmed : .unset) { status = .someday }
            }

            if let capMessage {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(Copy.capSheetTitle).font(Typo.sectionHeader)
                    Text(capMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
                    Button(Copy.sendToSomedayInstead) { Task { await promote(toSomeday: true) } }
                }
            }

            HStack {
                Spacer()
                Button(Copy.promote) { Task { await promote(toSomeday: false) } }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.cardPadding)
    }

    private func promote(toSomeday: Bool) async {
        let draft = ActionDraft(
            title: title, status: toSomeday ? .someday : status,
            contexts: contexts, timeEstimate: timeBucket?.minutes)
        do {
            let outcome = try await detailModel.promoteStep(at: stepIndex, draft: draft)
            switch outcome {
            case .success:
                dismiss()
            case .capReached:
                capMessage = Copy.capSheetBody
            case let .missingFields(fields):
                capMessage = Copy.missingFields(fields)
            }
        } catch {
            capMessage = "\(error)"
        }
    }
}

// MARK: - What's next? (P5)

/// Presented by the app shell on the `whatsNext` prompt after completing a project action.
/// **Owned by T22.**
public struct WhatsNextSheet: View {
    private let projectID: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var whatsNextModel: WhatsNextModel?
    @State private var freeText = ""
    @State private var capMessage: String?
    @State private var pendingSomedayStepIndex: Int?

    public init(project: NoteID) {
        self.projectID = project
    }

    public var body: some View {
        let next = whatsNextModel ?? WhatsNextModel(project: projectID, model: model)
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.whatsNext(project: next.title)).font(Typo.sectionHeader)

            // A long project's open steps scroll instead of pushing the buttons off the sheet.
            if !next.openSteps.isEmpty {
                OverflowScroll {
                    ForEach(next.openSteps) { entry in
                        Button {
                            Task { await promote(next, stepIndex: entry.stepIndex) }
                        } label: {
                            Text(entry.step.text).font(Typo.body)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("New action", text: $freeText)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                Button(Copy.done) { Task { await createFreeText(next) } }
                    .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let capMessage {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(capMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
                    Button(Copy.sendToSomedayInstead) { Task { await retryToSomeday(next) } }
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

    private func promote(_ next: WhatsNextModel, stepIndex: Int) async {
        do {
            switch try await next.promote(stepIndex: stepIndex) {
            case .success: dismiss()
            case .capReached:
                pendingSomedayStepIndex = stepIndex
                capMessage = Copy.capSheetBody
            case let .missingFields(fields):
                // R-3 — Someday is one tap away and always possible; Next needs the fields.
                pendingSomedayStepIndex = stepIndex
                capMessage = Copy.missingFields(fields)
            }
        } catch {
            capMessage = "\(error)"
        }
    }

    private func retryToSomeday(_ next: WhatsNextModel) async {
        if let stepIndex = pendingSomedayStepIndex {
            _ = try? await next.promoteToSomeday(stepIndex: stepIndex)
        } else {
            _ = try? await next.createActionInSomeday(title: freeText)
        }
        dismiss()
    }

    private func createFreeText(_ next: WhatsNextModel) async {
        do {
            switch try await next.createAction(title: freeText) {
            case .success: dismiss()
            case .capReached:
                pendingSomedayStepIndex = nil
                capMessage = Copy.capSheetBody
            case let .missingFields(fields):
                pendingSomedayStepIndex = nil
                capMessage = Copy.missingFields(fields)
            }
        } catch {
            capMessage = "\(error)"
        }
    }
}

// MARK: - Turn into project (A2)

/// Opened from the inline "Turn into project" button (T20 card, T25 detail): an action's
/// checkboxes become steps, title/why carry over, first step starts pre-selected for promotion.
/// **Owned by T22.**
public struct ConvertToProjectSheet: View {
    private let actionID: NoteID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var convertModel: ConvertToProjectModel?
    @State private var title = ""
    @State private var steps: [String] = []
    @State private var selectedStepIndex: Int? = 0
    @State private var capMessage: String?
    @State private var didSeed = false

    public init(action: NoteID) {
        self.actionID = action
    }

    public var body: some View {
        let convert = convertModel ?? ConvertToProjectModel(action: actionID, model: model)
        VStack(alignment: .leading, spacing: Spacing.l) {
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

            if let capMessage {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(capMessage).font(Typo.meta).foregroundStyle(Color.textSecondary)
                    Button(Copy.sendToSomedayInstead) { Task { await retryToSomeday(convert) } }
                }
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

    private func draft() -> ProjectDraft {
        ProjectDraft(title: title, why: convertModel?.action?.why ?? "", steps: steps)
    }

    private func convertNow(_ convert: ConvertToProjectModel) async {
        let draft = draft()
        do {
            switch try await convert.convert(draft, promoteStepIndex: selectedStepIndex) {
            case .success: dismiss()
            case .capReached:
                capMessage = Copy.capSheetBody
            case let .missingFields(fields):
                capMessage = Copy.missingFields(fields)
            }
        } catch {
            capMessage = "\(error)"
        }
    }

    private func retryToSomeday(_ convert: ConvertToProjectModel) async {
        guard let selectedStepIndex else { dismiss(); return }
        _ = try? await convert.promoteConvertedStepToSomeday(draft(), stepIndex: selectedStepIndex)
        dismiss()
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
