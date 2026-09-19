#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox
import FeatureProjects

// The four sub-steps of the sweep (§10.1).

// MARK: - 1a. Inbox to zero

/// Embeds the real processing session (I1–I7) rather than a review-only copy of it, so the
/// review clarifies items exactly the way the rest of the app does.
struct SweepInboxStep: View {
    @Bindable var session: ReviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: ReviewCopy.stepInbox,
                // No counter here: the embedded `InboxProcessingView` counts its own cards,
                // and the same "n of m left" twice on one screen is noise.
                counter: nil,
                symbol: ReviewSymbols.inbox)

            if session.isInboxZero {
                ContentUnavailableView(
                    Copy.emptyInboxTitle,
                    systemImage: ReviewSymbols.inbox,
                    description: Text(ReviewCopy.inboxZeroBody))
            } else {
                InboxProcessingView(showsChrome: false, onFinished: {})
                    .frame(minHeight: 420)
            }
        }
    }
}

// MARK: - 1b. Items deferred to review (I5)

/// Each item is shown **with the reason it did not fit** and a `System fix` field, so the
/// escape hatch feeds back into the system instead of just being a second inbox.
struct SweepDeferredStep: View {
    @Bindable var session: ReviewSession

    private enum Picker: String, Identifiable {
        case waiting, knowledge, project
        var id: String { rawValue }
    }

    @State private var draft = InboxSession.Draft()
    @State private var systemFix = ""
    @State private var loadedItem: NoteID?
    @State private var picker: Picker?
    @State private var knowledgeFolder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: ReviewCopy.stepDeferred,
                counter: session.deferredItems.isEmpty
                    ? nil
                    : Copy.counter(
                        remaining: session.deferredItems.count,
                        total: session.deferredItems.count + session.state.changes.deferredHandled),
                symbol: ReviewSymbols.deferred)

            if let item = session.currentDeferredItem {
                card(for: item)
            } else {
                ContentUnavailableView(
                    ReviewCopy.noDeferredTitle,
                    systemImage: ReviewSymbols.deferred,
                    description: Text(ReviewCopy.noDeferredBody))
            }
        }
        .onAppear { load(session.currentDeferredItem) }
        .onChange(of: session.currentDeferredItem?.id) { _, _ in
            load(session.currentDeferredItem)
        }
        .sheet(item: $picker) { pickerSheet($0) }
    }

    private func load(_ item: InboxItem?) {
        guard loadedItem != item?.id else { return }
        loadedItem = item?.id
        draft = item.map(InboxSession.Draft.init(item:)) ?? InboxSession.Draft()
        systemFix = ""
        knowledgeFolder = nil
    }

    private func card(for item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ItemCard {
                Text(ReviewCopy.deferredReasonLabel)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                Text(item.reviewReason ?? "")
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)

                Divider()

                TextField(Copy.whatPlaceholder, text: $draft.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.cardText)
                    .accessibilityLabel(Copy.inbox)

                ReviewTextField(
                    label: Copy.why, placeholder: Copy.whyPlaceholder, text: $draft.why)
                ReviewTextField(
                    label: Copy.what, placeholder: Copy.whatPlaceholder, text: $draft.what)

                chips

                Divider()

                ReviewTextField(
                    label: ReviewCopy.systemFixLabel,
                    placeholder: ReviewCopy.systemFixPlaceholder,
                    text: $systemFix)
            }

            targets(for: item)
            KeyLegendRow(DeferredSweep.targets.map {
                KeyLegendRow.Entry(key: $0.key, label: $0.title)
            })
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ContextChipGroup(contexts: session.snapshot.config.contexts, selection: $draft.contexts)
            TimeBucketChipGroup(selection: $draft.timeBucket)
            FlowLayout {
                DateValueChip(label: Copy.deferLabel, value: $draft.deferDate, today: session.today)
                DateValueChip(label: Copy.due, value: $draft.due, today: session.today)
            }
        }
    }

    private func targets(for item: InboxItem) -> some View {
        FlowLayout {
            ForEach(DeferredSweep.targets) { target in
                Button {
                    choose(target, item: item)
                } label: {
                    Label(target.title, systemImage: target.symbol)
                        .font(Typo.chip)
                }
                .keyboardShortcut(Self.shortcut(for: target), modifiers: [])
                .disabled(!DeferredSweep.isComplete(draft, for: target))
                .accessibilityLabel(target.title)
            }
        }
    }

    /// The same key map as the inbox card (STYLEGUIDE §3.6); `CardTarget` owns the mapping,
    /// this only turns it into a `KeyEquivalent`.
    private static func shortcut(for target: CardTarget) -> KeyEquivalent {
        switch target {
        case .next: .rightArrow
        case .backlog: .leftArrow
        case .maybe: .upArrow
        case .trash: .downArrow
        case .project: "p"
        case .knowledge: "k"
        case .waiting: "w"
        case .deferToReview: "r"
        }
    }

    private func choose(_ target: CardTarget, item: InboxItem) {
        switch target {
        case .waiting: picker = .waiting
        case .knowledge: picker = .knowledge
        case .project: picker = .project
        default:
            guard let decision = DeferredSweep.decision(target: target, draft: draft) else { return }
            file(decision, item: item)
        }
    }

    private func file(_ decision: InboxDecision, item: InboxItem) {
        let fix = systemFix
        Task { await session.fileDeferred(item, decision: decision, systemFix: fix) }
    }

    @ViewBuilder private func pickerSheet(_ picker: Picker) -> some View {
        switch picker {
        case .waiting:
            WaitingInfoSheet(today: session.today) { info in
                self.picker = nil
                guard let item = session.currentDeferredItem,
                      let decision = DeferredSweep.decision(
                        target: .waiting, draft: draft, waiting: info)
                else { return }
                file(decision, item: item)
            }
        case .knowledge:
            knowledgePicker
        case .project:
            projectPicker
        }
    }

    private var knowledgePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(Copy.knowledge).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            List(session.snapshot.knowledgeFolders, id: \.self) { folder in
                Button(folder) {
                    picker = nil
                    guard let item = session.currentDeferredItem,
                          let decision = DeferredSweep.decision(
                            target: .knowledge, draft: draft, knowledgeFolder: folder)
                    else { return }
                    file(decision, item: item)
                }
                .buttonStyle(.plain)
                .font(Typo.body)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(minWidth: 360, minHeight: 320)
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(Copy.project).font(Typo.sectionHeader).foregroundStyle(Color.ink)
            ProjectPicker(selection: $draft.project)
            Button(Copy.done) {
                picker = nil
                guard let item = session.currentDeferredItem,
                      let decision = DeferredSweep.decision(
                        target: .project, draft: draft, project: draft.project)
                else { return }
                file(decision, item: item)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.project == nil)
        }
        .padding(Spacing.cardPadding)
        .frame(minWidth: 360, minHeight: 320)
    }
}

// MARK: - 1c. Waiting (§10.1.3)

struct SweepWaitingStep: View {
    @Bindable var session: ReviewSession

    @State private var pending: (action: Action, choice: WaitingSweep.Choice)?
    @State private var followUp: Day?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: ReviewCopy.stepWaiting,
                counter: session.waitingItems.isEmpty ? nil : "\(session.waitingItems.count)",
                symbol: ReviewSymbols.waiting)

            if session.waitingItems.isEmpty {
                ContentUnavailableView(
                    ReviewCopy.noWaitingTitle,
                    systemImage: ReviewSymbols.waiting,
                    description: Text(ReviewCopy.noWaitingBody))
            } else {
                ForEach(session.waitingItems) { action in
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ActionRow(
                            action: action,
                            projectTitle: action.project.flatMap { session.snapshot.project($0)?.title },
                            badges: SignalPresentation.badges(
                                for: Rules.signals(for: action, today: session.today),
                                today: session.today))
                        if let days = session.waitingSince(action) {
                            Text(ReviewCopy.waitingSince(days: days))
                                .font(Typo.counter)
                                .foregroundStyle(Color.textSecondary)
                        }
                        HStack(spacing: Spacing.m) {
                            ForEach(WaitingSweep.Choice.allCases) { choice in
                                Button {
                                    start(choice, for: action)
                                } label: {
                                    Label(choice.title, systemImage: choice.symbol)
                                        .font(Typo.chip)
                                }
                                .accessibilityHint(choice.hint)
                            }
                        }
                        Divider()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            followUpSheet
        }
    }

    private func start(_ choice: WaitingSweep.Choice, for action: Action) {
        guard choice.needsFollowUp else {
            Task { await session.apply(choice, to: action) }
            return
        }
        followUp = nil
        pending = (action, choice)
    }

    /// The new follow-up date. The suggestion renders dashed and is **not** written until the
    /// user taps it (W1, STYLEGUIDE §3.1).
    @ViewBuilder private var followUpSheet: some View {
        if let pending {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(pending.choice.title).font(Typo.sectionHeader).foregroundStyle(Color.ink)
                Text(pending.choice.hint).font(Typo.meta).foregroundStyle(Color.textSecondary)
                DateValueChip(
                    label: Copy.followUp,
                    value: $followUp,
                    suggestion: session.suggestedFollowUp(for: pending.choice),
                    today: session.today)
                HStack {
                    Spacer()
                    Button(Copy.done) {
                        let captured = pending
                        let date = followUp
                        self.pending = nil
                        Task { await session.apply(captured.choice, to: captured.action, followUp: date) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(followUp == nil)
                }
            }
            .padding(Spacing.cardPadding)
            .frame(minWidth: 360)
        }
    }
}

// MARK: - 1d. Stalled projects (§10.1.4, P4)

struct SweepStalledStep: View {
    @Bindable var session: ReviewSession

    /// `NoteID` is not `Identifiable` (it is a value, not a row), so `.sheet(item:)` gets a
    /// wrapper rather than a conformance added to another target's type.
    private struct ProjectSheetItem: Identifiable {
        let id: NoteID
    }

    @State private var whatsNextProject: ProjectSheetItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ReviewStepHeader(
                title: ReviewCopy.stepStalled,
                counter: session.stalledProjects.isEmpty ? nil : "\(session.stalledProjects.count)",
                symbol: ReviewSymbols.stalled)

            if session.stalledProjects.isEmpty {
                ContentUnavailableView(
                    ReviewCopy.noStalledTitle,
                    systemImage: ReviewSymbols.stalled,
                    description: Text(ReviewCopy.noStalledBody))
            } else {
                ForEach(session.stalledProjects) { project in
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack(spacing: Spacing.s) {
                            Text(project.title).font(Typo.body).foregroundStyle(Color.ink)
                            Badge(SignalPresentation.badge(
                                for: Signal(kind: .stalled, step: .attention), today: session.today))
                            Spacer(minLength: Spacing.s)
                        }
                        Text(Copy.stalledProjectBody)
                            .font(Typo.meta)
                            .foregroundStyle(Color.textSecondary)
                        HStack(spacing: Spacing.m) {
                            ForEach(StalledSweep.Choice.allCases) { choice in
                                Button {
                                    apply(choice, to: project)
                                } label: {
                                    Label(choice.title, systemImage: choice.symbol)
                                        .font(Typo.chip)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
        }
        .sheet(item: $whatsNextProject) { item in
            VStack(alignment: .leading, spacing: Spacing.l) {
                WhatsNextSheet(project: item.id)
                Button(Copy.done) {
                    whatsNextProject = nil
                    if let project = session.snapshot.project(item.id) {
                        session.markStalledHandled(project)
                    }
                }
            }
            .padding(Spacing.cardPadding)
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    private func apply(_ choice: StalledSweep.Choice, to project: Project) {
        if choice == .addNextAction {
            whatsNextProject = ProjectSheetItem(id: project.id)
        } else {
            Task { await session.apply(choice, to: project) }
        }
    }
}
#endif
