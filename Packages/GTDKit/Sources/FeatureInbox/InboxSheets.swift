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
    /// `nil` = **nothing chosen yet** (§1 "no lying defaults") — the root `Knowledge` row shares
    /// path `""` with this sentinel's old value, which used to draw it pre-checked before any tap
    /// (T15). A last-used folder is offered only as the `.suggested` chip above; picking it is
    /// what sets this, never the fact that it exists.
    @State private var selection: String?
    /// I4b — an active project's folder, chosen instead of a `Knowledge/` folder.
    @State private var projectTarget: NoteID?
    @State private var notes: String = ""
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
                        projectTarget = nil
                    } label: {
                        folderRow(name: InboxCopy.knowledgeRoot, path: "")
                    }
                    .buttonStyle(.plain)

                    OutlineGroup(KnowledgeTree.build(folders), children: \.childNodes) { node in
                        Button {
                            selection = node.path
                            projectTarget = nil
                        } label: {
                            folderRow(name: node.name, path: node.path)
                        }
                        .buttonStyle(.plain)
                    }

                    if isAddingFolder {
                        HStack {
                            TextField(
                                InboxCopy.newFolderPlaceholder, text: $newFolder,
                                prompt: Text(InboxCopy.newFolderPlaceholder))
                                .textFieldStyle(.plain)
                                .labelsHidden()
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

                // I4b/D36 — project reference material is filed through this branch, so the
                // active projects' folders are targets next to the `Knowledge/` tree.
                Section(Copy.project) {
                    ForEach(session.activeProjects) { project in
                        Button {
                            projectTarget = project.id
                        } label: {
                            HStack {
                                Label(project.title, systemImage: Symbols.projects)
                                    .font(Typo.body)
                                    .foregroundStyle(Color.ink)
                                Spacer(minLength: 0)
                                if projectTarget == project.id {
                                    Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(InboxCopy.notesLabel) {
                    TextField(
                        InboxCopy.notesPlaceholder, text: $notes,
                        prompt: Text(InboxCopy.notesPlaceholder), axis: .vertical)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                }
            }
            .sheetFormStyle()
            .navigationTitle(Copy.knowledge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // R-4 — nothing to type: the note is named after the capture text.
                    // I4b/D36 — `Done` stays disabled until a target is chosen; choosing the
                    // root `Knowledge` folder (`selection == ""`) still counts as a choice.
                    Button(Copy.done) { save() }
                        .disabled(!KnowledgePickerModel.canSave(selection: selection, projectTarget: projectTarget))
                }
            }
        }
        .onAppear { folders = session.knowledgeFolders }
    }

    private func folderRow(name: String, path: String) -> some View {
        HStack {
            Label(name, systemImage: Symbols.area)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            if projectTarget == nil, selection == path {
                Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
            }
        }
        .contentShape(Rectangle())
    }

    private func addFolder() {
        projectTarget = nil
        let parent = selection ?? ""
        folders = KnowledgeTree.adding(newFolder, under: parent, to: folders)
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        selection = parent.isEmpty ? name : parent + "/" + name
        newFolder = ""
        isAddingFolder = false
    }

    private func save() {
        let target: KnowledgeTarget = projectTarget.map(KnowledgeTarget.project)
            ?? .folder(selection ?? "")
        let body = notes
        dismiss()
        Task { await session.confirmKnowledge(target: target, notes: body) }
    }

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - Project chip (I4a, R-8)

/// The `+ project` chip's picker: find a project in the area tree or by typing, or create one
/// **with a name only** (D35). The card stays an action either way — there is no "turn this
/// capture into a project" path here any more (D33).
struct ProjectSheet: View {
    @Bindable var session: InboxSession
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    var body: some View {
        NavigationStack {
            Form {
                // An explicit prompt and a hidden label: a Mac form otherwise draws the title as
                // a leading label and leaves the field itself empty.
                Section {
                    TextField(InboxCopy.pickProject, text: $search, prompt: Text(InboxCopy.pickProject))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                }
                if session.draft.project != nil || session.draft.newProjectTitle != nil {
                    Section {
                        Button(InboxCopy.clearProject) { choose(nil) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.gtdAccent)
                    }
                }
                // Ungrouped projects come first and carry no section header (ARCHITECTURE §6).
                ForEach(groups) { group in
                    if let title = group.title {
                        Section(title) { rows(of: group) }
                    } else {
                        Section { rows(of: group) }
                    }
                }
                if let name = creatableName {
                    Section {
                        Button {
                            session.createProject(named: name)
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
                    Button(InboxCopy.cancel) { cancel() }
                }
            }
        }
    }

    /// The whole sheet is `ProjectPicker.model(_:search:)` — the filtered tree (area-less first,
    /// no header) and whether the create row is offered. The view decides neither (T08).
    private var model: ProjectPickerModel { session.projectPicker(search: search) }

    private var groups: [ProjectGroup] { model.groups }

    /// `Create project "<text>"` — offered only when nothing matches exactly (STYLEGUIDE §3.6).
    private var creatableName: String? { model.createTitle }

    private func rows(of group: ProjectGroup) -> some View {
        ForEach(group.projects) { project in
            Button {
                choose(project.id)
            } label: {
                HStack {
                    Text(project.title)
                        .font(Typo.body)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if session.draft.project == project.id {
                        Image(systemName: Symbols.done)
                            .foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func choose(_ id: NoteID?) {
        session.chooseProject(id)
        dismiss()
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
    /// O3 — the reason field is the only control on this sheet; without a way to give up the
    /// keyboard it covered Cancel/Defer entirely. `@FocusState` + a keyboard toolbar Done button
    /// (the `ActionDetailView` pattern) plus interactive scroll dismissal fix that.
    @FocusState private var isReasonFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(InboxCopy.deferReasonLabel) {
                    TextField(
                        Copy.deferToReviewPrompt, text: $reason,
                        prompt: Text(Copy.deferToReviewPrompt), axis: .vertical)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .font(Typo.body)
                        .focused($isReasonFocused)
                }
            }
            .sheetFormStyle()
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(Copy.deferToReview)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.deferLabel) { save() }
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Copy.done) { isReasonFocused = false }
                }
                #endif
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

/// The forced choice: demote one of the current Next items, or cancel and decide differently.
/// Never an automatic re-route, and no "send to Someday instead" shortcut (STYLEGUIDE §3.6).
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
            }
            .scrollingSheetFrame()
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

    private func cancel() {
        dismiss()
        session.cancelSheet()
    }
}

// MARK: - More… (I4b)

/// The navbar's last slot: every list, not only the favourites. Tapping one files the card.
/// `New list…` creates a list and files the card into it; with no list at all the sheet says
/// what a list is instead of showing an empty table. Decisions are `InboxSession`'s.
struct MoreListsSheet: View {
    @Bindable var session: InboxSession

    var body: some View {
        ListChoiceSheet(
            lists: session.allLists,
            hasNoLists: session.hasNoLists,
            listsFolderName: session.listsFolderName,
            newListRefusal: session.newListRefusal,
            onChoose: { name in Task { await session.take(.list(name)) } },
            onCreate: { name in Task { await session.createListAndFile(name: name) } },
            onNameChanged: { session.clearNewListRefusal() },
            onCancel: { session.cancelSheet() })
    }
}

/// The list picker as a sheet: every list, `New list…` with its inline refusal, and the
/// no-lists explanation. Shared by the inbox's `More…` slot and a drop onto the Lists section
/// (E3), so the picker exists once; the owner decides what a choice does. `onCreate`'s owner
/// closes the sheet by clearing its own presentation once the list exists (a refused name keeps
/// it open — the refusal arrives through `newListRefusal`).
struct ListChoiceSheet: View {
    let lists: [GTDList]
    let hasNoLists: Bool
    let listsFolderName: String
    let newListRefusal: String?
    let onChoose: (String) -> Void
    let onCreate: (String) -> Void
    let onNameChanged: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newListName = ""
    @State private var isAddingList = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if hasNoLists && !isAddingList {
                    ContentUnavailableView {
                        Label(InboxCopy.noListsTitle, systemImage: Symbols.listBullet)
                    } description: {
                        Text(InboxCopy.noListsBody(folder: listsFolderName))
                    } actions: {
                        Button(InboxCopy.newList) { startAdding() }
                            .tint(Color.gtdAccent)
                    }
                } else {
                    List {
                        ForEach(lists) { list in
                            Button {
                                dismiss()
                                onChoose(list.name)
                            } label: {
                                Label(list.name, systemImage: Symbols.list(named: list.name))
                                    .font(Typo.body)
                                    .foregroundStyle(Color.ink)
                            }
                            .buttonStyle(.plain)
                        }
                        newListRow
                    }
                }
            }
            .scrollingSheetFrame()
            .navigationTitle(Copy.lists)
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

    @ViewBuilder private var newListRow: some View {
        if isAddingList {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    TextField(InboxCopy.newListPlaceholder, text: $newListName)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { create() }
                        .onChange(of: newListName) { onNameChanged() }
                    Button(InboxCopy.createList) { create() }
                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let refusal = newListRefusal {
                    Text(refusal).font(Typo.meta).foregroundStyle(Color.signalAttention)
                }
            }
        } else {
            Button {
                startAdding()
            } label: {
                Label(InboxCopy.newList, systemImage: Symbols.addValue)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.gtdAccent)
        }
    }

    private func startAdding() {
        isAddingList = true
        isNameFocused = true
    }

    /// The owner closes the sheet once the note has moved; a refused name keeps it open.
    private func create() {
        onCreate(newListName)
    }
}
#endif
