#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

// The sub-flows of I4/I5 and the forced cap choice of A3. Each one is a sheet over the card;
// cancelling always leaves the card and its draft untouched.

// MARK: - Knowledge (I4)

/// Category list plus free browsing and creating inside the `Knowledge/` tree. The last used
/// folder is a **suggested** (dashed) row — a suggestion, never a silent decision.
struct KnowledgeSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [String] = []
    @State private var selection: String = ""
    @State private var title: String = ""
    @State private var newFolder: String = ""
    @State private var isAddingFolder = false

    var body: some View {
        NavigationStack {
            Form {
                if let suggested = session.suggestedKnowledgeFolder, selection != suggested {
                    Section {
                        Chip(suggested, state: .suggested) { selection = suggested }
                    }
                }

                Section(InboxCopy.knowledgeFolderLabel) {
                    Button {
                        selection = ""
                    } label: {
                        folderRow(name: InboxCopy.knowledgeRoot, path: "")
                    }
                    .buttonStyle(.plain)

                    OutlineGroup(KnowledgeTree.build(folders), children: \.childNodes) { node in
                        Button {
                            selection = node.path
                        } label: {
                            folderRow(name: node.name, path: node.path)
                        }
                        .buttonStyle(.plain)
                    }

                    if isAddingFolder {
                        HStack {
                            TextField(InboxCopy.newFolderPlaceholder, text: $newFolder)
                                .textFieldStyle(.plain)
                            Button(Copy.done) { addFolder() }
                                .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            isAddingFolder = true
                        } label: {
                            Label(InboxCopy.newFolder, systemImage: Symbols.area)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                    }
                }

                Section(InboxCopy.knowledgeTitleLabel) {
                    TextField(InboxCopy.knowledgeTitleLabel, text: $title)
                        .textFieldStyle(.plain)
                }
            }
            .navigationTitle(Copy.knowledge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.done) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            folders = session.knowledgeFolders
            if title.isEmpty { title = session.draft.effectiveTitle }
        }
    }

    private func folderRow(name: String, path: String) -> some View {
        HStack {
            Label(name, systemImage: Symbols.area)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            if selection == path {
                Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
            }
        }
        .contentShape(Rectangle())
    }

    private func addFolder() {
        folders = KnowledgeTree.adding(newFolder, under: selection, to: folders)
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        selection = selection.isEmpty ? name : selection + "/" + name
        newFolder = ""
        isAddingFolder = false
    }

    private func save() {
        let folder = selection
        let noteTitle = title
        dismiss()
        Task { await session.confirmKnowledge(folder: folder, title: noteTitle) }
    }

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - Project (I4)

/// Pick an existing project (grouped by area) or create a new one — with a new area if needed —
/// and define the first next action(s).
struct ProjectSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case existing
        case new
        var id: String { rawValue }
        var title: String {
            self == .existing ? InboxCopy.existingProject : InboxCopy.newProject
        }
    }

    @State private var mode: Mode = .existing
    @State private var selected: NoteID?
    @State private var projectTitle = ""
    @State private var outcome = ""
    @State private var why = ""
    @State private var areaID: NoteID?
    @State private var newAreaTitle = ""
    @State private var firstActions: [String] = [""]

    var body: some View {
        NavigationStack {
            Form {
                Picker(InboxCopy.pickProject, selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if mode == .existing {
                    existingSection
                } else {
                    newSection
                }

                Section(InboxCopy.firstActionsLabel) {
                    ForEach(firstActions.indices, id: \.self) { index in
                        TextField(Copy.whatPlaceholder, text: binding(for: index))
                            .textFieldStyle(.plain)
                    }
                    Button(InboxCopy.addAnotherAction) { firstActions.append("") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                }
            }
            .navigationTitle(Copy.project)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.done) { save() }.disabled(!isComplete)
                }
            }
        }
        .onAppear {
            if firstActions == [""] {
                let derived = session.draft.effectiveTitle
                firstActions = [derived]
                if projectTitle.isEmpty { projectTitle = derived }
            }
            if session.projectGroups.isEmpty { mode = .new }
        }
    }

    @ViewBuilder private var existingSection: some View {
        if session.projectGroups.isEmpty {
            ContentUnavailableView(
                InboxCopy.noProjectsYet,
                systemImage: Symbols.projects,
                description: Text(InboxCopy.noProjectsYetBody))
        } else {
            // Ungrouped projects come first and carry no section header (ARCHITECTURE §6).
            ForEach(session.projectGroups) { group in
                if let title = group.title {
                    Section(title) { rows(of: group) }
                } else {
                    Section { rows(of: group) }
                }
            }
        }
    }

    private func rows(of group: ProjectGroup) -> some View {
        ForEach(group.projects) { project in
            Button {
                selected = project.id
            } label: {
                HStack {
                    Text(project.title)
                        .font(Typo.body)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if selected == project.id {
                        Image(systemName: Symbols.done)
                            .foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var newSection: some View {
        Section(InboxCopy.projectTitleLabel) {
            TextField(InboxCopy.projectTitleLabel, text: $projectTitle)
                .textFieldStyle(.plain)
        }
        Section(InboxCopy.outcomeLabel) {
            TextField(InboxCopy.outcomePlaceholder, text: $outcome, axis: .vertical)
                .textFieldStyle(.plain)
        }
        Section(Copy.why) {
            TextField(Copy.whyPlaceholder, text: $why, axis: .vertical)
                .textFieldStyle(.plain)
        }
        Section(InboxCopy.areaLabel) {
            ForEach(session.snapshot.areas) { area in
                Button {
                    areaID = area.id
                    newAreaTitle = ""
                } label: {
                    HStack {
                        Label(area.title, systemImage: Symbols.area)
                            .font(Typo.body)
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                        if areaID == area.id {
                            Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            TextField(InboxCopy.newAreaPlaceholder, text: $newAreaTitle)
                .textFieldStyle(.plain)
                .onChange(of: newAreaTitle) { _, newValue in
                    if !newValue.isEmpty { areaID = nil }
                }
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < firstActions.count ? firstActions[index] : "" },
            set: { if index < firstActions.count { firstActions[index] = $0 } })
    }

    private var isComplete: Bool {
        let hasAction = firstActions.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        switch mode {
        case .existing: return selected != nil && hasAction
        case .new: return !projectTitle.trimmingCharacters(in: .whitespaces).isEmpty && hasAction
        }
    }

    private func drafts(for project: Project?) -> [ActionDraft] {
        firstActions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                var draft = session.firstActionDraft(for: project)
                draft.title = line
                draft.what = line
                return draft
            }
    }

    private func save() {
        switch mode {
        case .existing:
            guard let id = selected else { return }
            let project = session.snapshot.project(id)
            let actions = drafts(for: project)
            dismiss()
            Task { await session.confirmExistingProject(id, actions: actions) }
        case .new:
            // A new project is created `active`, so its first actions may go to Next (P3).
            let actions = drafts(for: Project(id: NoteID(path: "new"), title: projectTitle, status: .active))
            let draft = ProjectDraft(
                title: projectTitle,
                area: newAreaTitle.trimmingCharacters(in: .whitespaces).isEmpty ? areaID : nil,
                newAreaTitle: newAreaTitle.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : newAreaTitle,
                outcome: outcome,
                why: why.isEmpty ? session.draft.why : why)
            dismiss()
            Task { await session.confirmNewProject(draft, firstActions: actions) }
        }
    }

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - Defer to review (I5)

/// The escape hatch: the app asks *why* the item does not fit, so the weekly review can fix the
/// system gap. `Defer` stays disabled until the reason is non-empty.
struct DeferToReviewSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(InboxCopy.deferReasonLabel) {
                    TextField(Copy.deferToReviewPrompt, text: $reason, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                }
            }
            .navigationTitle(Copy.deferToReview)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.deferLabel) { save() }
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let text = reason
        dismiss()
        Task { await session.confirmDeferToReview(reason: text) }
    }

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - Next is full (A3, I4)

/// The forced choice: demote one of the current Next items, or send this card to Backlog.
/// Never an automatic re-route (ARCHITECTURE §6).
struct CapSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.capSheetBody)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(session.capCandidates) { action in
                    HStack {
                        ActionRow(
                            action: action,
                            projectTitle: action.project.flatMap { session.snapshot.project($0)?.title })
                        Spacer(minLength: Spacing.s)
                        Button(Copy.demote) { demote(action.id) }
                            .buttonStyle(.bordered)
                    }
                }
                Section {
                    Button(Copy.sendToBacklogInstead) { sendToBacklog() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(Copy.capSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
            }
        }
    }

    private func demote(_ id: NoteID) {
        dismiss()
        Task { await session.demoteAndRetry(id) }
    }

    private func sendToBacklog() {
        dismiss()
        Task { await session.sendToBacklogInstead() }
    }

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - Full raw text

/// The whole captured text when the card had to collapse it (STYLEGUIDE §3.5).
struct FullTextSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField(InboxCopy.rawTextPlaceholder, text: $session.draft.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.screenMargin)
            }
            .background(Color.surface)
            .navigationTitle(Copy.inbox)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.done) {
                        dismiss()
                        session.cancelSheet()
                    }
                }
            }
        }
    }
}
#endif
