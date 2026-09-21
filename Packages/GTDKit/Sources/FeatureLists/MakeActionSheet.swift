#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox

// T09 reconcile: `FeatureInbox`'s own opened-action-card view (`InboxCardView`) is `internal`
// and, at the commit this target was built from, still being written by T09 — there is no public
// reusable view of `MakeActionModel`/`ActionCardState` to call into yet. This file is the
// thinnest host that can present one today, built only from what `FeatureInbox` and
// `DesignSystem` already export publicly (`MakeActionModel`, `ActionCardBar`, `WaitingInfoSheet`,
// `ProjectPickerModel`, `Chip`/`ContextChipGroup`/`TimeBucketChipGroup`, `SectionLabel`). It holds
// no decision of its own — every field, refusal and exit is `MakeActionModel`'s. When T09
// publishes its card view, replace this file's body with a call to it; `MakeActionSheet`'s own
// `init(model:item:)` signature should not need to change.

/// L4 "Make action": the opened action card, as a sheet, for one list item.
public struct MakeActionSheet: View {
    @State private var makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field: Hashable { case why, what }

    public init(model: AppModel, item: ListItem) {
        _makeAction = State(initialValue: MakeActionModel(model: model, item: item))
    }

    public var body: some View {
        // Local `@Bindable` shadow: `makeAction` is owned by `@State` (created once in `init`),
        // and this is what turns its computed `draft` property into `$makeAction.draft.*`
        // bindings for the fields below — the same pattern `@Bindable var session: InboxSession`
        // uses where the session is owned by the caller instead.
        @Bindable var makeAction = makeAction
        return NavigationStack {
            ScrollView {
                ItemCard {
                    Text(makeAction.item.title)
                        .font(Typo.cardText)
                        .foregroundStyle(Color.ink)

                    fieldSection(
                        label: Copy.why, isMissing: makeAction.isMissing(.why),
                        placeholder: Copy.whyPlaceholder, text: $makeAction.draft.why, field: .why)

                    fieldSection(
                        label: Copy.what, isMissing: makeAction.isMissing(.what),
                        placeholder: Copy.whatPlaceholder, text: $makeAction.draft.what, field: .what)

                    chipGroups
                }
                .padding(Spacing.screenMargin)
            }
            .shake(trigger: makeAction.shakeTrigger)
            .navigationTitle(makeAction.item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) {
                        makeAction.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ActionCardBar(
                    isFieldFocused: focus != nil,
                    onWaiting: { makeAction.sheet = .waiting },
                    onDone: { Task { await makeAction.take(.done) } },
                    onFileToNext: { Task { await makeAction.take(.next) } },
                    onFileToSomeday: { Task { await makeAction.take(.someday) } },
                    onDismissKeyboard: { focus = nil })
                    .padding(.bottom, Spacing.s)
            }
        }
        .onChange(of: makeAction.isFiled) { _, filed in
            if filed { dismiss() }
        }
        .onChange(of: makeAction.focusRequest) { _, request in
            switch request {
            case .why: focus = .why
            case .what: focus = .what
            default: break
            }
            if request != nil { makeAction.consumeFocusRequest() }
        }
        .onChange(of: focus) { _, entry in
            makeAction.isFieldFocused = entry != nil
        }
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .waiting:
                WaitingInfoSheet(today: makeAction.today) { info in
                    Task { await makeAction.confirmWaiting(info) }
                }
            case .project:
                MakeActionProjectSheet(makeAction: makeAction)
            case .cap:
                MakeActionCapSheet(makeAction: makeAction)
            default:
                EmptyView()
            }
        }
    }

    private var sheetBinding: Binding<InboxSession.Sheet?> {
        Binding(get: { makeAction.sheet }, set: { makeAction.sheet = $0 })
    }

    @ViewBuilder private func fieldSection(
        label: String, isMissing: Bool, placeholder: String, text: Binding<String>, field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(label, isMissing: isMissing)
            TextField(
                "", text: text,
                prompt: Text(placeholder).foregroundStyle(Color.textTertiary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
        }
    }

    private var chipGroups: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.contextGroupLabel, isMissing: makeAction.isMissing(.context),
                    font: Typo.meta, foreground: .textSecondary)
                ContextChipGroup(contexts: makeAction.contexts, selection: $makeAction.draft.contexts)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.timeGroupLabel, isMissing: makeAction.isMissing(.timeEstimate),
                    font: Typo.meta, foreground: .textSecondary)
                TimeBucketChipGroup(selection: $makeAction.draft.timeBucket)
            }
            FlowLayout {
                Chip(
                    projectChipTitle,
                    state: projectChipTitle == Copy.project ? .unset : .confirmed,
                    symbol: projectChipTitle == Copy.project ? Symbols.addValue : nil
                ) {
                    makeAction.sheet = .project
                }
            }
        }
    }

    private var projectChipTitle: String {
        makeAction.projectChipTitle(in: makeAction.snapshot) ?? Copy.project
    }
}

/// The `+ project` chip's picker (I4a), built from `MakeActionModel.projectPicker(search:)` — the
/// same public model `FeatureInbox.ProjectSheet` reads, without depending on that internal view.
private struct MakeActionProjectSheet: View {
    let makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(InboxCopy.pickProject, text: $search)
                        .textFieldStyle(.plain)
                }
                if makeAction.draft.project != nil || makeAction.draft.newProjectTitle != nil {
                    Section {
                        Button(InboxCopy.clearProject) { choose(nil) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.gtdAccent)
                    }
                }
                ForEach(model.groups) { group in
                    if let title = group.title {
                        Section(title) { rows(of: group) }
                    } else {
                        Section { rows(of: group) }
                    }
                }
                if let name = model.createTitle {
                    Section {
                        Button {
                            makeAction.createProject(named: name)
                            dismiss()
                        } label: {
                            Label(InboxCopy.createProject(name), systemImage: Symbols.addValue)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.gtdAccent)
                    }
                }
            }
            .navigationTitle(Copy.project)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) { dismiss() }
                }
            }
        }
    }

    private var model: ProjectPickerModel { makeAction.projectPicker(search: search) }

    private func rows(of group: ProjectGroup) -> some View {
        ForEach(group.projects) { project in
            Button {
                choose(project.id)
            } label: {
                HStack {
                    Text(project.title).font(Typo.body).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if makeAction.draft.project == project.id {
                        Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func choose(_ id: NoteID?) {
        makeAction.chooseProject(id)
        dismiss()
    }
}

/// `Next is full` (A3, I4): demote one Next item, or cancel. Never automatic (D14).
private struct MakeActionCapSheet: View {
    let makeAction: MakeActionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.capSheetBody)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(makeAction.capCandidates) { action in
                    HStack {
                        ActionRow(
                            action: action,
                            projectTitle: action.project.flatMap { makeAction.snapshot.project($0)?.title })
                        Spacer(minLength: Spacing.s)
                        Button(Copy.demote) {
                            dismiss()
                            Task { await makeAction.demoteAndRetry(action.id) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle(Copy.capSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) {
                        dismiss()
                        makeAction.cancelSheet()
                    }
                }
            }
        }
    }
}
#endif
