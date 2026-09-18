#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureProjects
import GTDFixtures

/// Where the vault lives on disk, for "Open in Obsidian". The app shell (T40) sets it; feature
/// targets never touch the file system themselves.
private struct VaultRootPathKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var vaultRootPath: String? {
        get { self[VaultRootPathKey.self] }
        set { self[VaultRootPathKey.self] = newValue }
    }
}

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

    var body: some View {
        Group {
            if let editor, editor.draft != nil {
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                TextField(
                    OverviewCopy.titlePlaceholder,
                    text: Binding(get: { editor.title }, set: { editor.setTitle($0) }))
                    .textFieldStyle(.plain)
                    .font(Typo.screenTitle)
                    .foregroundStyle(Color.ink)

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

                section(Copy.why, placeholder: Copy.whyPlaceholder, text: Binding(
                    get: { editor.why }, set: { editor.setWhy($0) }))

                section(Copy.what, placeholder: Copy.whatPlaceholder, text: Binding(
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

                Button {
                    if let url = ObsidianLink.url(for: editor.id, vaultRoot: vaultRootPath) {
                        openURL(url)
                    }
                } label: {
                    Label(OverviewCopy.openInObsidian, systemImage: OverviewSymbols.openExternally)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// `waiting` is reached through `WaitingInfoSheet` (W1), never by tapping a chip.
    private var statusChoices: [ActionStatus] {
        [.next, .inProgress, .backlog, .maybe, .waiting]
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
        _ label: String, placeholder: String, text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(label).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .lineLimit(3...)
        }
    }

    /// A refused command (STYLEGUIDE §4.3: no alerts for validation — inline, in place).
    @ViewBuilder private func errorBanner(_ editor: ActionEditModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(errorTitle(editor.lastError))
                .font(Typo.meta)
                .foregroundStyle(Color.ink)
            if isCapRefusal(editor.lastError) {
                Text(Copy.capSheetBody)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                Button(Copy.sendToBacklogInstead) {
                    editor.clearError()
                    editor.setStatus(.backlog)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.gtdAccent)
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

    private func errorTitle(_ error: (any Error)?) -> String {
        switch error as? GTDError {
        case .nextCapReached: Copy.capSheetTitle
        case .titleCollision: OverviewCopy.titleTaken
        case .notFound: OverviewCopy.missingActionTitle
        default: OverviewCopy.notSaved
        }
    }
}

#Preview("Detail · backlog") {
    ActionDetailPreview(status: .backlog)
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
