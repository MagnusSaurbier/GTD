#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureProjects
import GTDFixtures

/// The note editor of the right-hand column (E3) — also the iPhone's action detail.
///
/// Editing autosaves; there are no Save buttons (STYLEGUIDE §4.4). All of the autosave logic
/// lives in `ActionEditModel`, which is unit-tested; this view is only the surface.
public struct ActionDetailView: View {
    private let action: NoteID
    private let onRename: (NoteID) -> Void

    /// `onRename` lets the enclosing shell follow the `NoteID` a rename creates (A1: the file
    /// name is the title). The default keeps the frozen one-argument signature usable.
    public init(action: NoteID, onRename: @escaping (NoteID) -> Void = { _ in }) {
        self.action = action
        self.onRename = onRename
    }

    public var body: some View {
        ActionDetailEditor(id: action, onRename: onRename)
    }
}

private struct ActionDetailEditor: View {
    let id: NoteID
    let onRename: (NoteID) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.vaultRootPath) private var vaultRootPath
    @State private var editor: ActionEditModel?
    @State private var isWaitingSheetPresented = false
    @State private var isConvertPresented = false
    /// Which text entry has the keyboard (P2). `nil` = none, which is what Done, a scroll and a
    /// tap outside a field all set.
    @FocusState private var focus: TextEntry?
    /// Bumped when Return submits the title: a wrapping field keeps the typed line break on
    /// screen unless it is rebuilt from the (single-line) draft.
    @State private var titleGeneration = 0
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    private enum TextEntry: Hashable {
        case title, why, what
    }

    var body: some View {
        Group {
            if let editor, editor.isClosed {
                ContentUnavailableView(
                    OverviewCopy.missingActionTitle,
                    systemImage: Symbols.done,
                    description: Text(OverviewCopy.closedActionBody))
            } else if let editor, editor.draft != nil {
                form(editor)
            } else if editor?.isMissing == true {
                ContentUnavailableView(
                    OverviewCopy.missingActionTitle,
                    systemImage: Symbols.trash,
                    description: Text(OverviewCopy.missingActionBody))
            } else {
                Color.clear
            }
        }
        .task(id: id) {
            // Our own rename hands us back the note we are already editing — keep the state
            // (and any keystrokes typed since the save) instead of rebuilding the editor.
            if let editor, editor.id == id { return }
            let fresh = ActionEditModel(model: model, id: id)
            fresh.onRename = { onRename($0) }
            editor = fresh
        }
        .onChange(of: model.snapshot) { _, _ in
            editor?.refresh()
        }
        .onDisappear {
            let leaving = editor
            Task { await leaving?.flush() }
        }
    }

    // MARK: - Form

    @ViewBuilder private func form(_ editor: ActionEditModel) -> some View {
        let today = model.today()
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                // Wraps instead of scrolling sideways (P2). Still one line in the vault: the
                // model folds line breaks away and reports a Return as "submit".
                TextField(
                    OverviewCopy.titlePlaceholder,
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
                    .id(TextEntry.title)

                if editor.lastError != nil {
                    errorBanner(editor)
                }

                labelled(OverviewCopy.status) {
                    FlowLayout {
                        ForEach(statusChoices, id: \.self) { choice in
                            Chip(
                                Copy.status(choice),
                                state: editor.status == choice ? .confirmed : .unset
                            ) {
                                if choice == .waiting {
                                    isWaitingSheetPresented = true
                                } else {
                                    editor.setStatus(choice)
                                }
                            }
                        }
                    }
                }

                labelled(OverviewCopy.context) {
                    ContextChipGroup(
                        contexts: model.snapshot.config.contexts,
                        selection: Binding(
                            get: { editor.contexts }, set: { editor.setContexts($0) }))
                }

                labelled(OverviewCopy.time) {
                    TimeBucketChipGroup(selection: Binding(
                        get: { editor.timeBucket },
                        set: { editor.setTimeEstimate($0?.minutes) }))
                }

                FlowLayout {
                    DateValueChip(
                        label: Copy.deferLabel,
                        value: Binding(get: { editor.deferDate }, set: { editor.setDeferDate($0) }),
                        today: today)
                    DateValueChip(
                        label: Copy.due,
                        value: Binding(get: { editor.due }, set: { editor.setDue($0) }),
                        today: today)
                }

                labelled(Copy.project) {
                    ProjectPicker(selection: Binding(
                        get: { editor.project }, set: { editor.setProject($0) }))
                }

                section(Copy.why, entry: .why, placeholder: Copy.whyPlaceholder, text: Binding(
                    get: { editor.why }, set: { editor.setWhy($0) }))

                section(Copy.what, entry: .what, placeholder: Copy.whatPlaceholder, text: Binding(
                    get: { editor.what }, set: { editor.setWhat($0) }))

                if editor.suggestsProject {
                    Button {
                        isConvertPresented = true
                    } label: {
                        Label(Copy.turnIntoProject, systemImage: Symbols.projects)
                    }
                    .buttonStyle(.plain)
                    .font(Typo.meta)
                    .foregroundStyle(Color.gtdAccent)
                }

                Divider()

                #if os(macOS)
                // P8 — the iPhone has these in its bottom bar (thumb reach, STYLEGUIDE §1.7).
                HStack(spacing: Spacing.l) {
                    Button {
                        close(editor, trash: false)
                    } label: {
                        Label(Copy.done, systemImage: Symbols.done)
                    }
                    Button {
                        close(editor, trash: true)
                    } label: {
                        Label(Copy.trash, systemImage: Symbols.trash)
                    }
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.gtdAccent)
                #endif

                // No vault root (fixtures) means no link Obsidian could resolve: no button.
                if let url = ObsidianLink.url(for: editor.id, vaultRoot: vaultRootPath) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(OverviewCopy.openInObsidian, systemImage: OverviewSymbols.openExternally)
                    }
                    .buttonStyle(.plain)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Spacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A tap that no chip, button or field took lands here: it puts the keyboard away.
            .contentShape(Rectangle())
            .onTapGesture { focus = nil }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        // P7/O2 — the last row rests clear of the floating bottom-bar buttons (⋯, Done) at
        // scroll rest. `Spacing.minHitTarget` (44 pt) is their real footprint; `Spacing.xl`
        // clears their own padding plus the safe-area/home-indicator margin below them. The
        // tab bar is already hidden behind this push (`PhoneShell`'s `.toolbar(.hidden,
        // for: .tabBar)`), so it needs no extra allowance here.
        .contentMargins(.bottom, Spacing.minHitTarget + Spacing.xl, for: .scrollContent)
        #endif
        .onChange(of: focus) { _, entry in
            editor.setTitleHeld(entry == .title)
            guard let entry else {
                Task { await editor.flush() }        // field blur writes the edit now
                return
            }
            // The keyboard is still on its way up; scroll once it has taken its space, or a
            // wrapping field at the bottom of the form stays underneath it (P2).
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard focus == entry else { return }
                withAnimation { proxy.scrollTo(entry, anchor: .center) }
            }
        }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Copy.done) { focus = nil }
            }
            // P8 — tick off or trash from the detail, in the lower half of the screen.
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button(role: .destructive) {
                        close(editor, trash: true)
                    } label: {
                        Label(Copy.trash, systemImage: Symbols.trash)
                    }
                } label: {
                    Label(OverviewCopy.more, systemImage: OverviewSymbols.more)
                }
                Spacer()
                Button {
                    close(editor, trash: false)
                } label: {
                    Label(Copy.done, systemImage: Symbols.done)
                        .labelStyle(.titleAndIcon)
                }
                .tint(Color.gtdAccent)
            }
        }
        #endif
        .sheet(isPresented: $isWaitingSheetPresented) {
            WaitingInfoSheet(
                initial: editor.waiting,
                suggestedWho: suggestedWho,
                today: today,
                onSave: { editor.setWaiting($0) })
        }
        .sheet(isPresented: $isConvertPresented) {
            ConvertToProjectSheet(action: editor.id)
        }
    }

    /// Return in the title: give the keyboard back and rebuild the field from the draft.
    private func submitTitleIfAsked(_ submitted: Bool) {
        guard submitted else { return }
        focus = nil
        titleGeneration += 1
    }

    /// Complete / trash (P8). The list's undo toast covers both; a refusal shows in the inline
    /// banner, and the detail only leaves the screen once the command went through.
    private func close(_ editor: ActionEditModel, trash: Bool) {
        focus = nil
        Task {
            guard await (trash ? editor.trash() : editor.complete()) else { return }
            #if os(iOS)
            dismiss()
            #endif
        }
    }

    /// `waiting` is reached through `WaitingInfoSheet` (W1), never by tapping a chip.
    private var statusChoices: [ActionStatus] {
        [.next, .inProgress, .someday, .waiting]
    }

    /// Names already used elsewhere, offered as dashed suggestions in the waiting sheet.
    private var suggestedWho: [String] {
        Array(Set(model.snapshot.actions.compactMap(\.waitingFor))).sorted().prefix(4).map { $0 }
    }

    @ViewBuilder private func labelled<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(label).font(Typo.meta).foregroundStyle(Color.textSecondary)
            content()
        }
    }

    @ViewBuilder private func section(
        _ label: String, entry: TextEntry, placeholder: String, text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(label).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .listEditingShortcuts()
                .font(Typo.body)
                .lineLimit(3...)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: entry)
        }
        .id(entry)
    }

    /// A refused command (STYLEGUIDE §4.3: no alerts for validation — inline, in place).
    ///
    /// STYLEGUIDE §3.6 ("Next at cap"): demote one **or cancel** — no "send to Someday instead"
    /// shortcut. This banner *is* that cap refusal for an existing action (moving it to Next
    /// through the status chips), so it offers no such shortcut either; the person clears the
    /// error and swipes/chips their way to Someday themselves, same as the inbox and the Next
    /// list's own cap sheet (ARCHITECTURE §6, T11).
    @ViewBuilder private func errorBanner(_ editor: ActionEditModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(errorTitle(editor.lastError))
                .font(Typo.meta)
                .foregroundStyle(Color.ink)
            if isCapRefusal(editor.lastError) {
                Text(Copy.capSheetBody)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fillQuiet, in: Radius.chipShape)
    }

    private func isCapRefusal(_ error: (any Error)?) -> Bool {
        guard let error = error as? GTDError else { return false }
        if case .nextCapReached = error { return true }
        return false
    }

    /// R-3 — a `missingFields` refusal names the gap (`Copy.missingFields`), same wording the
    /// shell's alert uses for every other flow that goes through `report` (deliverable 6).
    private func errorTitle(_ error: (any Error)?) -> String {
        switch error as? GTDError {
        case .nextCapReached: Copy.capSheetTitle
        case let .missingFields(fields): Copy.missingFields(fields)
        case .titleCollision: OverviewCopy.titleTaken
        case .notFound: OverviewCopy.missingActionTitle
        default: OverviewCopy.notSaved
        }
    }
}

#Preview("Detail · someday") {
    ActionDetailPreview(status: .someday)
}

#Preview("Detail · waiting") {
    ActionDetailPreview(status: .waiting)
}

#Preview("Detail · next, dark") {
    ActionDetailPreview(status: .next).preferredColorScheme(.dark)
}

/// Picks the first sample action in a given status, so every status has a preview.
private struct ActionDetailPreview: View {
    let status: ActionStatus

    var body: some View {
        let snapshot = Fixtures.sampleSnapshot
        let action = snapshot.actions.first { $0.status == status } ?? snapshot.actions[0]
        return ActionDetailView(action: action.id)
            .environment(AppModel(
                backend: InMemoryBackend(snapshot: snapshot),
                snapshot: snapshot,
                today: { Fixtures.today }))
    }
}
#endif
