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
    @State private var newFolder: String = ""
    @State private var isAddingFolder = false
    /// Paths of the folders whose children are shown (#24). Starts empty: the tree opens
    /// collapsed, as the stock outline did.
    @State private var expandedFolders: Set<String> = []
    /// The Mac keyboard walk (#77): suggestion → folders (`→`/`←` open and close one) →
    /// projects → `Done`, on the first stop from the start; `nil` while a field has the keys.
    @State private var walk: KeyWalk? = KeyWalk.initial
    @FocusState private var hasWalkFocus: Bool
    @FocusState private var isNotesFocused: Bool
    @FocusState private var isNewFolderFocused: Bool

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
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let walk {
                    KeyWalkLegendLine(
                        press: Copy.walkChoose,
                        hasNextRow: walk.hasNextRow(in: rows.map(\.count)))
                }
            }
            .keyWalkKeys(
                focus: $hasWalkFocus,
                onMove: { walk = (walk ?? KeyWalk()).moved(by: $0, in: rows.map(\.count)) },
                onPress: press,
                onNextRow: { walk = (walk ?? KeyWalk()).advanced(in: rows.map(\.count)) },
                onArrow: openOrClose)
            .onChange(of: isNotesFocused) { _, focused in
                if focused { walk = nil }
            }
            .onChange(of: isNewFolderFocused) { _, focused in
                if focused { walk = nil }
            }
        }
        // #94 — a folder name typed and left (anything but `Cancel`) comes back in its field.
        .keepsDraft($newFolder, key: InputDraftKey.newKnowledgeFolder, in: session.inputDrafts)
        .onAppear {
            folders = session.knowledgeFolders
            if session.inputDrafts.hasDraft(for: InputDraftKey.newKnowledgeFolder) { isAddingFolder = true }
        }
    }

    private var form: some View {
            Form {
                if let suggested = shownSuggestion {
                    Section {
                        Chip(
                            suggested, state: .suggested,
                            isKeyHighlighted: isHighlighted(.suggestion(suggested))
                        ) {
                            selection = suggested
                            point(at: .suggestion(suggested))
                        }
                        .id(KnowledgePickStop.suggestion(suggested))
                    }
                }

                Section(InboxCopy.knowledgeFolderLabel) {
                    Button {
                        selection = ""
                        projectTarget = nil
                        point(at: .folder(""))
                    } label: {
                        folderRow(name: InboxCopy.knowledgeRoot, path: "")
                    }
                    .buttonStyle(.plain)
                    .keyHighlight(isHighlighted(.folder("")), in: Self.rowShape)
                    .id(KnowledgePickStop.folder(""))

                    // Own tree rows instead of `OutlineGroup`: inside a `Form` on macOS the
                    // stock outline draws a child's label *left* of its parent (where the
                    // parent's chevron sits) and animates open/close. Here every level is
                    // shifted right by one step and toggling is instant (#24).
                    folderTreeRows(KnowledgeTree.build(folders), depth: 0)

                    if isAddingFolder {
                        HStack {
                            TextField(
                                InboxCopy.newFolderPlaceholder, text: $newFolder,
                                prompt: Text(InboxCopy.newFolderPlaceholder))
                                .textFieldStyle(.plain)
                                .labelsHidden()
                                .focused($isNewFolderFocused)
                                .onSubmit {
                                    guard !newFolder.trimmingCharacters(in: .whitespaces).isEmpty
                                    else { return }
                                    addFolder()
                                }
                            Button(Copy.done) { addFolder() }
                                .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            startAddingFolder()
                        } label: {
                            Label(InboxCopy.newFolder, systemImage: Symbols.area)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                        .keyHighlight(isHighlighted(.newFolder), in: Self.rowShape)
                        .id(KnowledgePickStop.newFolder)
                    }
                }

                // I4b/D36 — project reference material is filed through this branch, so the
                // active projects' folders are targets next to the `Knowledge/` tree.
                Section(Copy.project) {
                    ForEach(session.activeProjects) { project in
                        Button {
                            projectTarget = project.id
                            point(at: .project(project.id))
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
                        .keyHighlight(isHighlighted(.project(project.id)), in: Self.rowShape)
                        .id(KnowledgePickStop.project(project.id))
                    }
                }

                Section(InboxCopy.notesLabel) {
                    // The card's own notes panel (#85): what is typed here survives `Cancel`
                    // and is kept with the card when the session closes.
                    NoteEditor(text: $session.draft.notes, prompt: InboxCopy.notesPlaceholder)
                        // `⌘↩` past the last line hands the keys to the walk, on `Done`.
                        .onAdvance { point(at: .done) }
                        .focused($isNotesFocused)
                        .accessibilityLabel(InboxCopy.notesLabel)
                }

                #if os(macOS)
                // `Done` again inside the sheet, where the walk can draw its ring on it (the
                // toolbar's own button cannot carry one).
                if walk != nil {
                    Section {
                        HStack {
                            Spacer(minLength: 0)
                            Button(Copy.done) { save() }
                                .buttonStyle(.bordered)
                                .disabled(!canSave)
                                .keyHighlight(isHighlighted(.done), in: Self.rowShape)
                        }
                        .id(KnowledgePickStop.done)
                    }
                }
                #endif
            }
    }

    // MARK: Keyboard walk (#77)

    private static let rowShape = RoundedRectangle(cornerRadius: 6)

    private var canSave: Bool {
        KnowledgePickerModel.canSave(selection: selection, projectTarget: projectTarget)
    }

    private var shownSuggestion: String? {
        guard let suggested = session.suggestedKnowledgeFolder, selection != suggested
        else { return nil }
        return suggested
    }

    private var rows: [[KnowledgePickStop]] {
        KnowledgePickStop.walkRows(
            suggestion: shownSuggestion,
            tree: KnowledgeTree.build(folders),
            expanded: expandedFolders,
            projects: session.activeProjects.map(\.id),
            isAddingFolder: isAddingFolder)
    }

    private func isHighlighted(_ stop: KnowledgePickStop) -> Bool {
        walk?.stop(in: rows) == stop
    }

    /// A click (or a field's `↩`/`⌘↩`) puts the highlight on `stop` and the keys on the walk.
    private func point(at stop: KnowledgePickStop) {
        guard KeyWalk.isAvailable else { return }
        isNotesFocused = false
        isNewFolderFocused = false
        walk = KeyWalk.position(of: stop, in: rows) ?? KeyWalk.first(in: rows.map(\.count))
        hasWalkFocus = true
    }

    /// `↩` does what a click on the highlighted row does.
    private func press() {
        switch walk?.stop(in: rows) {
        case let .suggestion(path):
            selection = path
            projectTarget = nil
            point(at: .folder(path))
        case let .folder(path):
            selection = path
            projectTarget = nil
        case .newFolder:
            startAddingFolder()
        case let .project(id):
            projectTarget = id
        case .done:
            if canSave { save() }
        case nil:
            walk = KeyWalk.first(in: rows.map(\.count))
        }
    }

    /// `→` opens, `←` closes the highlighted folder of the tree.
    private func openOrClose(_ direction: Int) {
        guard case let .folder(path)? = walk?.stop(in: rows), !path.isEmpty else { return }
        if direction > 0 {
            expandedFolders.insert(path)
        } else {
            expandedFolders.remove(path)
        }
    }

    private func startAddingFolder() {
        isAddingFolder = true
        walk = nil
        isNewFolderFocused = true
    }

    /// One row per visible folder, depth-first. Collapsed folders hide their subtree; the set
    /// of open folders is device state for the sheet's lifetime only.
    @ViewBuilder
    private func folderTreeRows(_ nodes: [FolderNode], depth: Int) -> some View {
        ForEach(nodes) { node in
            Button {
                selection = node.path
                projectTarget = nil
                point(at: .folder(node.path))
            } label: {
                folderRow(name: node.name, path: node.path, node: node, depth: depth)
            }
            .buttonStyle(.plain)
            .keyHighlight(isHighlighted(.folder(node.path)), in: Self.rowShape)
            .id(KnowledgePickStop.folder(node.path))

            if expandedFolders.contains(node.path) {
                AnyView(folderTreeRows(node.children, depth: depth + 1))
            }
        }
    }

    private func folderRow(
        name: String, path: String, node: FolderNode? = nil, depth: Int = 0
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            // Every row reserves the chevron's width so that siblings without children line
            // up with siblings that have some; the indent per level is one chevron slot.
            Group {
                if let node, node.childNodes != nil {
                    Button {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            if !expandedFolders.insert(node.path).inserted {
                                expandedFolders.remove(node.path)
                            }
                        }
                    } label: {
                        Image(systemName: expandedFolders.contains(node.path)
                              ? Symbols.collapse : Symbols.nextMonth)
                            .font(Typo.controlGlyph)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: Spacing.l, height: Spacing.l)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expandedFolders.contains(node.path)
                                        ? InboxCopy.collapseFolder : InboxCopy.expandFolder)
                } else {
                    Color.clear.frame(width: Spacing.l, height: Spacing.l)
                }
            }
            .padding(.leading, CGFloat(depth) * Spacing.l)
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
        // The new folder shows under its parent, so the walk can stand on it.
        if !parent.isEmpty { expandedFolders.insert(parent) }
        if let selection { point(at: .folder(selection)) }
    }

    private func save() {
        let target: KnowledgeTarget = projectTarget.map(KnowledgeTarget.project)
            ?? .folder(selection ?? "")
        dismiss()
        Task { await session.confirmKnowledge(target: target) }
    }

    private func cancel() {
        // The one deliberate discard (#94).
        session.inputDrafts.clear(InputDraftKey.newKnowledgeFolder)
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

    /// `ProjectChoiceSheet` is the one picker (search, `Clear`, the tree, `Create project`, the
    /// keyboard walk); the card only says what a choice does.
    var body: some View {
        ProjectChoiceSheet(
            picker: { session.projectPicker(search: $0) },
            current: session.draft.project,
            canClear: session.draft.project != nil || session.draft.newProjectTitle != nil,
            onChoose: { session.chooseProject($0) },
            onCreate: { session.createProject(named: $0) },
            onCancel: { session.cancelSheet() })
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
    /// The Mac keyboard walk (#77) over `Defer` · `Cancel`. The sheet opens in the reason field
    /// (there is nothing to defer without one); `↩` there hands the keys to the walk on `Defer`.
    @State private var walk: KeyWalk?
    @FocusState private var hasWalkFocus: Bool

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
                        .onSubmit { point(at: .deferIt) }
                }
                #if os(macOS)
                // The two buttons again, in the sheet itself, so the walk has something to
                // draw on (the toolbar's own buttons cannot carry the ring).
                if walk != nil {
                    Section {
                        HStack(spacing: Spacing.m) {
                            Spacer(minLength: 0)
                            Button(InboxCopy.cancel) { cancel() }
                                .keyHighlight(isHighlighted(.cancel), in: Self.buttonShape)
                            Button(Copy.deferLabel) { point(at: .deferIt); save() }
                                .disabled(!canSave)
                                .keyHighlight(isHighlighted(.deferIt), in: Self.buttonShape)
                        }
                        .buttonStyle(.bordered)
                    } footer: {
                        KeyWalkLegendLine(press: Copy.walkChoose, hasNextRow: false)
                    }
                }
                #endif
            }
            .sheetFormStyle()
            .keyWalkKeys(
                focus: $hasWalkFocus,
                onMove: { walk = (walk ?? KeyWalk()).moved(by: $0, in: Self.rowCounts) },
                onPress: press)
            .onAppear { isReasonFocused = true }
            .onChange(of: isReasonFocused) { _, focused in
                if focused { walk = nil }
            }
            // #94 — the reason survives every way out but `Cancel`; deferring clears it.
            .keepsDraft($reason, key: session.deferReasonDraftKey, in: session.inputDrafts)
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
                        .disabled(!canSave)
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

    private static let buttonShape = RoundedRectangle(cornerRadius: 6)
    private static let rowCounts = DeferReviewStop.walkRows.map(\.count)

    private var canSave: Bool { !reason.trimmingCharacters(in: .whitespaces).isEmpty }

    private func isHighlighted(_ stop: DeferReviewStop) -> Bool {
        walk?.stop(in: DeferReviewStop.walkRows) == stop
    }

    private func point(at stop: DeferReviewStop) {
        guard KeyWalk.isAvailable else { return }
        isReasonFocused = false
        walk = KeyWalk.position(of: stop, in: DeferReviewStop.walkRows)
        hasWalkFocus = true
    }

    /// `↩` presses the highlighted button. `Defer` without a reason goes back to the field.
    private func press() {
        switch walk?.stop(in: DeferReviewStop.walkRows) {
        case .deferIt:
            if canSave { save() } else { isReasonFocused = true }
        case .cancel:
            cancel()
        case nil:
            break
        }
    }

    private func save() {
        let text = reason
        dismiss()
        Task { await session.confirmDeferToReview(reason: text) }
    }

    private func cancel() {
        // The one deliberate discard (#94).
        if let key = session.deferReasonDraftKey { session.inputDrafts.clear(key) }
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
    /// The Mac keyboard walk (#77) over the `Demote` buttons, on the first one from the start.
    @State private var walk: KeyWalk? = KeyWalk.initial
    @FocusState private var hasWalkFocus: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.capSheetBody)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(Array(session.capCandidates.enumerated()), id: \.element.id) { index, action in
                    HStack {
                        ActionRow(
                            action: action,
                            projectTitle: action.project.flatMap { session.snapshot.project($0)?.title })
                        Spacer(minLength: Spacing.s)
                        Button(Copy.demote) { demote(action.id) }
                            .buttonStyle(.bordered)
                            .keyHighlight(
                                walk?.highlight(inRow: 0) == index,
                                in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if walk != nil, !session.capCandidates.isEmpty {
                    KeyWalkLegendLine(press: Copy.walkChoose, hasNextRow: false)
                }
            }
            .keyWalkKeys(
                focus: $hasWalkFocus,
                onMove: { walk = (walk ?? KeyWalk()).moved(by: $0, in: rowCounts) },
                onPress: {
                    guard let index = walk?.clamped(in: rowCounts)?.index else { return }
                    demote(session.capCandidates[index].id)
                })
            .scrollingSheetFrame()
            .navigationTitle(Copy.capSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { cancel() }
                }
            }
        }
    }

    private var rowCounts: [Int] { [session.capCandidates.count] }

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
            onCancel: { session.cancelSheet() },
            drafts: session.inputDrafts)
    }
}

/// The list picker as a sheet: every list, `New list…` with its inline refusal, and the
/// no-lists explanation. Shared by the inbox's `More…` slot and a drop onto the Lists section
/// (E3), so the picker exists once; the owner decides what a choice does. `onCreate`'s owner
/// closes the sheet by clearing its own presentation once the list exists (a refused name keeps
/// it open — the refusal arrives through `newListRefusal`).
struct ListChoiceSheet: View {
    @Environment(\.listIcons) private var listIcons
    let lists: [GTDList]
    let hasNoLists: Bool
    let listsFolderName: String
    let newListRefusal: String?
    let onChoose: (String) -> Void
    let onCreate: (String) -> Void
    let onNameChanged: () -> Void
    let onCancel: () -> Void
    /// #94 — where `New list…` keeps a typed name: every way out but `Cancel` keeps it, and
    /// the picker opens with it again. The owner clears it once the list exists.
    var drafts: InputDrafts? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var newListName = ""
    @State private var isAddingList = false
    @FocusState private var isNameFocused: Bool
    /// The Mac keyboard walk (#77): on the first list the moment the sheet opens, `nil` while
    /// the new list's name field has the keys.
    @State private var walk: KeyWalk? = KeyWalk.initial
    @FocusState private var hasWalkFocus: Bool

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
                            .keyHighlight(isHighlighted(.newList), in: Self.rowShape)
                    }
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(lists) { list in
                                Button {
                                    choose(list.name)
                                } label: {
                                    Label(list.name, systemImage: Symbols.list(named: list.name, icons: listIcons))
                                        .font(Typo.body)
                                        .foregroundStyle(Color.ink)
                                }
                                .buttonStyle(.plain)
                                .keyHighlight(isHighlighted(.list(list.name)), in: Self.rowShape)
                                .id(ListPickStop.list(list.name))
                            }
                            newListRow
                        }
                        .onChange(of: walk) { _, walk in
                            guard let stop = walk?.stop(in: rows) else { return }
                            proxy.scrollTo(stop)
                        }
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
            .onChange(of: isNameFocused) { _, focused in
                if focused { walk = nil }
            }
            .scrollingSheetFrame()
            .keepsDraft($newListName, key: InputDraftKey.newListInPicker, in: drafts)
            .onAppear {
                // A name kept from last time opens the field it was typed in.
                if drafts?.hasDraft(for: InputDraftKey.newListInPicker) == true {
                    isAddingList = true
                    walk = nil
                }
            }
            .navigationTitle(Copy.lists)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) {
                        // The one deliberate discard (#94).
                        drafts?.clear(InputDraftKey.newListInPicker)
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
            .keyHighlight(isHighlighted(.newList), in: Self.rowShape)
            .id(ListPickStop.newList)
        }
    }

    static let rowShape = RoundedRectangle(cornerRadius: 6)

    private var rows: [[ListPickStop]] {
        ListPickStop.walkRows(lists: lists.map(\.name), isAddingList: isAddingList)
    }

    private func isHighlighted(_ stop: ListPickStop) -> Bool {
        walk?.stop(in: rows) == stop
    }

    /// `↩` does what a click on the highlighted row does.
    private func press() {
        switch walk?.stop(in: rows) {
        case let .list(name): choose(name)
        case .newList: startAdding()
        case nil: walk = KeyWalk.first(in: rows.map(\.count))
        }
    }

    private func choose(_ name: String) {
        dismiss()
        onChoose(name)
    }

    private func startAdding() {
        isAddingList = true
        isNameFocused = true
        walk = nil
    }

    /// The owner closes the sheet once the note has moved; a refused name keeps it open.
    private func create() {
        onCreate(newListName)
    }
}
#endif
