#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem

/// **Make action** (L4) as a view: the opened action card alone, over `MakeActionModel`, for
/// `FeatureLists` (T10) to present as a sheet. Same card body and bar as the inbox's step 2a —
/// `InboxCardView`'s field rendering is shared through `ActionCardFields`, so nobody copies the
/// asterisk rule, the chip layout or the checklist behaviour.
///
/// `FeatureLists` presents this over `.sheet(item:)`:
/// ```swift
/// .sheet(item: $listItemToPromote) { item in
///     MakeActionCardView(model: MakeActionModel(model: appModel, item: item, bindings: keys)) {
///         listItemToPromote = nil
///     }
/// }
/// ```
/// `onFinished` is called once the card is filed (`model.isFiled`) or cancelled (`Esc` /
/// `Close`); the host is responsible for dismissing the sheet.
public struct MakeActionCardView: View {
    @Bindable private var model: MakeActionModel
    private let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: CardField?
    /// Mac: key focus of the card area, taken back when a field is blurred (single-key shortcuts).
    @FocusState private var hasKeyFocus: Bool
    @State private var translation: CGSize = .zero
    @State private var dragTarget: InboxExit?
    @State private var cardSize: CGSize = .zero
    @State private var shake: CGFloat = 0

    public init(model: MakeActionModel, onFinished: @escaping () -> Void) {
        self.model = model
        self.onFinished = onFinished
    }

    public var body: some View {
        content
            .toolbar { toolbarContent }
            .sheet(item: $model.sheet) { sheet in
                sheetContent(sheet)
                #if os(iOS)
                    .presentationDetents(sheet == .cap ? [.large] : [.medium, .large])
                #endif
            }
            .onChange(of: model.shakeTrigger) { old, new in
                guard new > old else { return }
                switch model.focusRequest {
                case .why: focus = .why
                case .what: focus = .what
                default: break
                }
                model.consumeFocusRequest()
                guard !reduceMotion else { return }
                withAnimation(Motion.standard) { shake += 1 }
            }
            .onChange(of: focus) { _, field in
                model.isFieldFocused = field != nil
            }
            .task {
                // Presented as a `.sheet` (unlike `InboxProcessingView`'s `fullScreenCover`,
                // which only moves focus on a later step transition): focusing `Why?` while the
                // sheet is still animating in leaves a stuck/ghost keyboard `Done` accessory
                // behind the real one until the keyboard is dismissed once. Wait for the
                // presentation to settle first (STYLEGUIDE §3.6 "focus goes to `Why?`").
                guard focus == nil else { return }
                try? await Task.sleep(nanoseconds: UInt64(MotionTiming.sheetSettle * 1_000_000_000))
                guard focus == nil, !model.isFiled else { return }
                focus = .why
            }
            .onChange(of: model.isFiled) { _, filed in
                if filed { onFinished() }
            }
            .sensoryFeedback(.error, trigger: model.shakeTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: dragTarget)
            #if os(macOS)
            .focusable()
            .focused($hasKeyFocus)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { press(.arrowLeft) }
            .onKeyPress(.rightArrow) { press(.arrowRight) }
            .onKeyPress(characters: Self.keyCharacters, phases: .down) { handle($0) }
            // Not `.onKeyPress(.escape)`: a focused field never lets it fire (see `onEscapeKey`).
            .onEscapeKey { escape() }
            .interactiveDismissDisabled()
            #endif
    }

    @ViewBuilder private var content: some View {
        #if os(iOS)
        GeometryReader { viewport in
            ScrollView {
                card
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.l)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { focus = nil }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if focus == nil {
                ActionCardBar(
                    isFieldFocused: false,
                    onWaiting: { Task { await model.take(.waiting) } },
                    onDone: { Task { await model.take(.done) } },
                    onFileToNext: { fly(to: .next) },
                    onFileToSomeday: { fly(to: .someday) })
                    .padding(.bottom, Spacing.s)
            } else {
                // Mirrors `InboxSessionView.keyboardBar`: a single `Done` control replaces the
                // action bar while a field has the keyboard, never both at once.
                HStack {
                    Spacer(minLength: 0)
                    Button(Copy.done) { focus = nil }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("inbox.keyboardDone")
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.s)
            }
        }
        #else
        VStack(spacing: Spacing.l) {
            Spacer(minLength: 0)
            card
            ActionCardBar(
                isFieldFocused: focus != nil,
                onWaiting: { Task { await model.take(.waiting) } },
                onDone: { Task { await model.take(.done) } },
                onFileToNext: { fly(to: .next) },
                onFileToSomeday: { fly(to: .someday) },
                onDismissKeyboard: { focus = nil })
            Text(model.legend.map { "\($0.key) \($0.label)" }.joined(separator: " · "))
                .font(Typo.counter)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenMargin)
        #endif
    }

    private var card: some View {
        MakeActionCardBody(
            model: model, focus: $focus, dragTarget: dragTarget, translation: translation,
            shake: shake)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { cardSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in cardSize = newValue }
                }
            }
            #if os(iOS)
            .gesture(dragGesture, including: focus == nil ? .all : .subviews)
            #endif
    }

    #if os(iOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DragThresholds.axisLock)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let context = model.dragContext
                translation = DragResolver.lockedTranslation(dx: dx, dy: dy, in: context)
                switch DragResolver.outcome(dx: dx, dy: dy, cardSize: cardSize, in: context) {
                case let .file(exit): dragTarget = exit
                case .collapse, nil: dragTarget = nil
                }
            }
            .onEnded { value in
                let outcome = DragResolver.outcome(
                    dx: value.translation.width, dy: value.translation.height,
                    cardSize: cardSize, in: model.dragContext)
                dragTarget = nil
                if case let .file(exit) = outcome {
                    fly(to: exit)
                } else {
                    withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) {
                        translation = .zero
                    }
                }
            }
    }
    #endif

    private func fly(to exit: InboxExit) {
        let wasFiled = model.isFiled
        withAnimation(reduceMotion ? Motion.reduced : Motion.cardExit) {
            translation = exitTranslation(for: exit)
        }
        Task {
            await model.take(exit)
            if model.isFiled != wasFiled {
                translation = .zero
            } else {
                withAnimation(reduceMotion ? Motion.reduced : Motion.cardReturn) {
                    translation = .zero
                }
            }
        }
    }

    private func exitTranslation(for exit: InboxExit) -> CGSize {
        let width = max(cardSize.width, 320) * 1.5
        switch exit {
        case .next: return CGSize(width: width, height: 0)
        case .someday: return CGSize(width: -width, height: 0)
        default: return .zero
        }
    }

    #if os(macOS)
    private static let keyCharacters: CharacterSet = CharacterSet.alphanumerics
        .union(.punctuationCharacters)
        .union(.symbols)

    private func press(_ stroke: KeyStroke) -> KeyPress.Result {
        guard focus == nil,
              let key = KeyMap.resolve(stroke: stroke, step: model.step, bindings: model.keyBindings)
        else { return .ignored }
        perform(key)
        return .handled
    }

    private func escape() {
        model.isFieldFocused = focus != nil
        if focus != nil {
            focus = nil
            hasKeyFocus = true
        } else {
            Task { await model.handle(.escape) }
            onFinished()
        }
    }

    private func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        guard focus == nil, let character = keyPress.characters.first,
              let key = KeyMap.resolve(
                character, shift: keyPress.modifiers.contains(.shift),
                command: keyPress.modifiers.contains(.command),
                step: model.step, bindings: model.keyBindings)
        else { return .ignored }
        perform(key)
        return .handled
    }

    private func perform(_ key: InboxKey) {
        if case let .command(command) = key, command == .cardNext {
            fly(to: .next)
        } else if case let .command(command) = key, command == .cardSomeday {
            fly(to: .someday)
        } else {
            Task { await model.handle(key) }
        }
    }
    #endif

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(Copy.close) {
                model.cancel()
                onFinished()
            }
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: InboxSession.Sheet) -> some View {
        switch sheet {
        case .waiting:
            WaitingInfoSheet(today: model.today) { info in
                Task { await model.confirmWaiting(info) }
            }
        case .project:
            MakeActionProjectSheet(model: model)
        case .cap:
            MakeActionCapSheet(model: model)
        case .knowledge, .deferToReview, .more:
            // Not reachable from `MakeActionModel.exits` (there is no step 1 under this card).
            EmptyView()
        }
    }
}

/// The card body alone (STYLEGUIDE §3.5 step 2a), reusing exactly the field layout
/// `InboxCardView` draws for the action card — meta line, the capture-text title, `Why?`,
/// `What?` and the chips, with the same asterisk rule.
private struct MakeActionCardBody: View {
    @Bindable var model: MakeActionModel
    @FocusState.Binding var focus: CardField?
    let dragTarget: InboxExit?
    let translation: CGSize
    let shake: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rotation: Double {
        guard !reduceMotion else { return 0 }
        let fraction = max(min(translation.width / 400, 1), -1)
        return fraction * DragThresholds.maxRotationDegrees
    }

    var body: some View {
        ItemCard {
            if let created = model.item.created {
                HStack(spacing: Spacing.s) {
                    Text(InboxCopy.captureStamp(created, today: model.today))
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            // Always an *opened* action card (there is no step 1 here) — it hugs its content
            // like `InboxCardView`'s 2a/2b, rather than reserving `rawTextMaxHeight` the way a
            // `ScrollView` would even for one line of text (T15 defect 5).
            TextField(
                "", text: $model.draft.title,
                prompt: Text(InboxCopy.rawTextPlaceholder).foregroundStyle(Color.textTertiary),
                axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.cardText)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: .text)
                .accessibilityLabel(InboxCopy.rawTextPlaceholder)
                .id(CardField.text)

            fieldSection(
                label: Copy.why, isMissing: model.isMissing(.why), placeholder: Copy.whyPlaceholder,
                text: $model.draft.why, field: .why)
            whatSection
            chips
        }
        .offset(x: translation.width, y: translation.height)
        .rotationEffect(.degrees(rotation))
        .modifier(ShakeEffect(travel: shake))
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(model.exits, id: \.self) { exit in
                Button(exit.title) { Task { await model.take(exit) } }
            }
        }
    }

    private func fieldSection(
        label: String, isMissing: Bool, placeholder: String, text: Binding<String>, field: CardField
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(label, isMissing: isMissing)
            TextField(
                "", text: text,
                prompt: Text(placeholder).foregroundStyle(Color.textTertiary), axis: .vertical)
                .textFieldStyle(.plain)
                .listEditingShortcuts()
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
        }
        .id(field)
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                SectionLabel(Copy.what, isMissing: model.isMissing(.what))
                Spacer(minLength: 0)
                Button(InboxCopy.checklist) {
                    model.draft.what = ChecklistText.isChecklist(model.draft.what)
                        ? ChecklistText.asPlainText(model.draft.what)
                        : ChecklistText.asChecklist(model.draft.what)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
            }
            TextField(
                "", text: $model.draft.what,
                prompt: Text(Copy.whatPlaceholder).foregroundStyle(Color.textTertiary),
                axis: .vertical)
                .textFieldStyle(.plain)
                .listEditingShortcuts()
                .font(Typo.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focus, equals: .what)
                .accessibilityLabel(Copy.what)
                .onChange(of: model.draft.what) { _, newValue in
                    let formatted = ChecklistText.autoFormat(newValue)
                    if formatted != newValue { model.draft.what = formatted }
                }
            if model.draft.suggestsProject {
                Button {
                    model.sheet = .project
                } label: {
                    Label(Copy.turnIntoProject, systemImage: Symbols.projects)
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.gtdAccent)
            }
        }
        .id(CardField.what)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.contextGroupLabel, isMissing: model.isMissing(.context),
                    font: Typo.meta, foreground: .textSecondary)
                ContextChipGroup(contexts: model.contexts, selection: $model.draft.contexts)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionLabel(
                    InboxCopy.timeGroupLabel, isMissing: model.isMissing(.timeEstimate),
                    font: Typo.meta, foreground: .textSecondary)
                TimeBucketChipGroup(selection: $model.draft.timeBucket)
            }
            FlowLayout {
                DateValueChip(label: Copy.deferLabel, value: $model.draft.deferDate, today: model.today)
                DateValueChip(label: Copy.due, value: $model.draft.due, today: model.today)
                Chip(
                    projectChipTitle,
                    state: isProjectChosen ? .confirmed : .unset,
                    symbol: isProjectChosen ? nil : "plus"
                ) {
                    model.sheet = .project
                }
            }
        }
    }

    private var chosenProjectTitle: String? { model.projectChipTitle(in: model.snapshot) }
    private var isProjectChosen: Bool { chosenProjectTitle != nil }
    private var projectChipTitle: String {
        chosenProjectTitle ?? Copy.unsetValueChipTitle(Copy.project)
    }
}

/// `+ project` for `MakeActionModel` — same picker rules as the inbox's (`ProjectPicker`), just
/// over the list-item model instead of `InboxSession`.
private struct MakeActionProjectSheet: View {
    @Bindable var model: MakeActionModel
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
                if model.draft.project != nil || model.draft.newProjectTitle != nil {
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
                            model.createProject(named: name)
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
                        model.cancelSheet()
                    }
                }
            }
        }
    }

    private var pickerModel: ProjectPickerModel { model.projectPicker(search: search) }

    private func rows(of group: ProjectGroup) -> some View {
        ForEach(group.projects) { project in
            Button {
                choose(project.id)
            } label: {
                HStack {
                    Text(project.title).font(Typo.body).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if model.draft.project == project.id {
                        Image(systemName: Symbols.done).foregroundStyle(Color.gtdAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func choose(_ id: NoteID?) {
        model.chooseProject(id)
        dismiss()
    }
}

/// `Next is full` for `MakeActionModel` — same forced choice as the inbox's `CapSheet`.
private struct MakeActionCapSheet: View {
    @Bindable var model: MakeActionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.capSheetBody).font(Typo.meta).foregroundStyle(Color.textSecondary)
                }
                ForEach(model.capCandidates) { action in
                    HStack {
                        ActionRow(
                            action: action,
                            projectTitle: action.project.flatMap { model.snapshot.project($0)?.title })
                        Spacer(minLength: Spacing.s)
                        Button(Copy.demote) {
                            dismiss()
                            Task { await model.demoteAndRetry(action.id) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .scrollingSheetFrame()
            .navigationTitle(Copy.capSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(InboxCopy.cancel) {
                        dismiss()
                        model.cancelSheet()
                    }
                }
            }
        }
    }
}
#endif
