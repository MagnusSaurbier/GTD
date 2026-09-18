#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// The default screen (E1/E2): filter chips, the chase section, then the Next list.
/// **Owned by T21.**
public struct NextView: View {
    private let mode: NextViewMode
    private let onOpen: (NoteID) -> Void
    /// Quick add (Mac `⌘N`, iPhone toolbar button): capture to inbox and jump into processing
    /// of that one card (I7). `FeatureNext` never imports `FeatureInbox`, so the app shell
    /// supplies this. `nil` hides the button (e.g. a host that has nowhere to route it yet).
    private let onQuickCapture: (() -> Void)?
    @Environment(AppModel.self) private var model

    public init(
        mode: NextViewMode,
        onOpen: @escaping (NoteID) -> Void,
        onQuickCapture: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onOpen = onOpen
        self.onQuickCapture = onQuickCapture
    }

    public var body: some View {
        NextListContent(model: model, mode: mode, onOpen: onOpen, onQuickCapture: onQuickCapture)
    }
}

/// Owns the `NextListModel` with stable identity across `NextView.body` re-evaluations.
///
/// `AppModel` only exists once `body` runs (it comes from `@Environment`), but `NextListModel`
/// must be created exactly once per screen so the user's filter picks survive every snapshot
/// update — recreating it in `body` itself would reset `contexts`/`timeAvailable` on every
/// command. Receiving `model` as an `init` parameter (not via `@Environment` on this view) is
/// what lets `@State` seed `NextListModel` a single time.
private struct NextListContent: View {
    let onOpen: (NoteID) -> Void
    let onQuickCapture: (() -> Void)?
    @State private var list: NextListModel
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var toastLabel: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var waitingSheetAction: Action?
    @State private var deferSheetAction: Action?
    /// A row command the reducer refused. Never swallowed with `try?` — every row action goes
    /// through `run(_:)`, which lands the failure here so it reaches the person instead of
    /// disappearing silently.
    @State private var errorMessage: String?

    init(
        model: AppModel,
        mode: NextViewMode,
        onOpen: @escaping (NoteID) -> Void,
        onQuickCapture: (() -> Void)?
    ) {
        self.onOpen = onOpen
        self.onQuickCapture = onQuickCapture
        _list = State(initialValue: NextListModel(model: model, mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            Group {
                if list.isEmpty {
                    emptyStateView
                } else {
                    listView
                }
            }
        }
        .navigationTitle(Copy.next)
        .toolbar { quickCaptureToolbar }
        .safeAreaInset(edge: .bottom) { toastView }
        .onChange(of: model.undoLabel) { _, newValue in
            guard let newValue else { return }
            showToast(newValue)
        }
        .sheet(item: $waitingSheetAction) { action in
            WaitingInfoSheet(initial: action.waiting, today: list.today) { info in
                run { try await list.setWaiting(action, info) }
            }
        }
        .sheet(item: $deferSheetAction) { action in
            DeferSheet(action: action, today: list.today) { newValue in
                run { try await list.setDefer(action, to: newValue) }
            }
        }
        .alert(
            errorMessage ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(Copy.done) { errorMessage = nil }
        }
    }

    /// Runs a row command; a thrown `GTDError` is never swallowed (§1 "no lying UI" — a refused
    /// command has to be visible, not just quietly undone in the UI's own head).
    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = message(for: error)
            }
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case let GTDError.invalid(reason): reason
        case GTDError.nextCapReached: Copy.capSheetTitle
        default: Copy.actionFailed
        }
    }

    // MARK: - Filter bar (E1)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.l) {
                ContextChipGroup(
                    contexts: list.availableContexts,
                    selection: Binding(get: { list.contexts }, set: { list.setContexts($0) }))
                TimeBucketChipGroup(selection: timeBucketBinding)
                if list.isFiltered {
                    Button(Copy.clearFilters) { list.clearFilters() }
                        .font(Typo.chip)
                        .foregroundStyle(Color.textSecondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.s)
        }
    }

    /// `TimeBucketChipGroup` is the same single-select chip row I3 uses for a time *estimate*;
    /// here it picks how much time is *available*, so the bound value is the bucket whose
    /// `minutes` equals the current filter — round-trips exactly since the chip always writes
    /// 10/30/60/90.
    private var timeBucketBinding: Binding<TimeBucket?> {
        Binding(
            get: { TimeBucket(minutes: list.timeAvailable) },
            set: { list.setTimeAvailable($0?.minutes) })
    }

    // MARK: - Empty states

    @ViewBuilder private var emptyStateView: some View {
        if list.isFiltered {
            ContentUnavailableView {
                Label(list.emptyStateTitle, systemImage: Symbols.next)
            } description: {
                Text(list.emptyStateBody)
            } actions: {
                Button(Copy.clearFilters) { list.clearFilters() }
            }
        } else {
            ContentUnavailableView(
                list.emptyStateTitle, systemImage: Symbols.next, description: Text(list.emptyStateBody))
        }
    }

    // MARK: - List

    private var listView: some View {
        List {
            if !list.chase.isEmpty {
                Section(Copy.chase) {
                    ForEach(list.chase, id: \.id) { chaseRow($0) }
                }
            }
            Section {
                ForEach(list.items, id: \.id) { nextRow($0) }
            } header: {
                capHeader
            }
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: list.items.map(\.id))
        .animation(Motion.standard(reduceMotion: reduceMotion), value: list.chase.map(\.id))
    }

    /// STYLEGUIDE §2.2: a plain count below the cap, an attention badge `15/15` at the cap,
    /// overdue styling above it. Never a meter.
    private var capHeader: some View {
        HStack {
            Spacer()
            if let badge = list.capBadge {
                Badge(badge)
            } else {
                Text("\(list.capCount)")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("\(list.capCount) in Next")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder private func nextRow(_ action: Action) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ActionRow(
                action: action,
                projectTitle: list.projectTitle(for: action),
                badges: list.badges(for: action),
                onComplete: { run { try await list.complete(action) } })
                .contentShape(Rectangle())
                .onTapGesture { onOpen(action.id) }
            if list.showsChecklist(action) {
                checklist(for: action)
            }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(Copy.done) { run { try await list.complete(action) } }
                .tint(Color.signalDone)
        }
        .swipeActions(edge: .leading) {
            Button("\(Copy.demote) to \(Copy.backlog)") {
                run { try await list.demoteToBacklog(action) }
            }
            .tint(Color.fillQuiet)
        }
        #endif
        .contextMenu {
            if action.status != .inProgress {
                Button(Copy.start) { run { try await list.start(action) } }
            }
            Button("\(Copy.demote) to \(Copy.backlog)") {
                run { try await list.demoteToBacklog(action) }
            }
            Button(Copy.waiting) { waitingSheetAction = action }
            Button(Copy.deferLabel) { deferSheetAction = action }
        }
    }

    @ViewBuilder private func chaseRow(_ action: Action) -> some View {
        ActionRow(
            action: action,
            projectTitle: list.projectTitle(for: action),
            badges: list.badges(for: action),
            onComplete: { run { try await list.resolveChase(action) } })
            .contentShape(Rectangle())
            .onTapGesture { onOpen(action.id) }
            #if os(iOS)
            .swipeActions(edge: .trailing) {
                Button(Copy.resolved) { run { try await list.resolveChase(action) } }
                    .tint(Color.signalDone)
            }
            .swipeActions(edge: .leading) {
                Button(Copy.bumpFollowUp(days: 7)) { run { try await list.bumpFollowUp(action) } }
                    .tint(Color.fillQuiet)
            }
            #endif
            .contextMenu {
                Button(Copy.bumpFollowUp(days: 7)) { run { try await list.bumpFollowUp(action) } }
                Button(Copy.resolved) { run { try await list.resolveChase(action) } }
            }
    }

    /// A2 — inline checkboxes once an action has more than one; ticking the last one offers
    /// to complete the action instead of doing it automatically (§1 "no lying UI").
    @ViewBuilder private func checklist(for action: Action) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(action.checkboxes.enumerated()), id: \.offset) { index, checkbox in
                Button {
                    run { try await list.toggleCheckbox(action, index: index) }
                } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: checkbox.done ? Symbols.checkboxOn : Symbols.checkboxOff)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(checkbox.done ? Color.ink : Color.textSecondary)
                        Text(checkbox.text)
                            .font(Typo.meta)
                            .foregroundStyle(checkbox.done ? Color.textSecondary : Color.ink)
                            .strikethrough(checkbox.done)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checkbox.done ? [.isSelected] : [])
            }
            if list.allChecked(action) {
                Button {
                    run { try await list.complete(action) }
                } label: {
                    Label(Copy.done, systemImage: Symbols.done)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.gtdAccent)
                .font(Typo.meta)
                .accessibilityLabel("\(Copy.done) \(action.title)")
            }
        }
        .padding(.leading, Spacing.xl)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var quickCaptureToolbar: some ToolbarContent {
        if let onQuickCapture {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onQuickCapture) {
                    Label(Copy.quickCapture, systemImage: Symbols.capture)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Undo toast (N6)

    @ViewBuilder private var toastView: some View {
        if let toastLabel {
            UndoToast(label: toastLabel) {
                toastTask?.cancel()
                self.toastLabel = nil
                Task { await model.undo() }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.bottom, Spacing.m)
            .transition(.opacity)
        }
    }

    /// One toast at a time — a new one replaces the old (STYLEGUIDE §3.8). Auto-dismisses
    /// after `MotionTiming.toastDuration`; the underlying undo bookkeeping in `AppModel` is
    /// unaffected by the toast's own visibility, so `⌘Z` keeps working after it fades.
    private func showToast(_ label: String) {
        toastTask?.cancel()
        toastLabel = label
        toastTask = Task {
            try? await Task.sleep(for: .seconds(MotionTiming.toastDuration))
            guard !Task.isCancelled else { return }
            toastLabel = nil
        }
    }
}

/// The row's "Defer" context-menu action opens this — a `DateValueChip` in a small sheet
/// (STYLEGUIDE §3.1: popover on Mac, `.medium` sheet on iOS; a context-menu item cannot host
/// a popover directly, so this wraps the same chip in the smallest sheet that can).
private struct DeferSheet: View {
    let action: Action
    let today: Day
    let onChange: (Day?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Day?

    init(action: Action, today: Day, onChange: @escaping (Day?) -> Void) {
        self.action = action
        self.today = today
        self.onChange = onChange
        _value = State(initialValue: action.deferDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(Copy.deferLabel).font(Typo.sectionHeader)
            DateValueChip(label: Copy.deferLabel, value: $value, today: today)
            HStack {
                Spacer()
                Button(Copy.done) {
                    onChange(value)
                    dismiss()
                }
            }
        }
        .padding(Spacing.cardPadding)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}

#Preview("Full") {
    NavigationStack {
        NextView(mode: .full, onOpen: { _ in }, onQuickCapture: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("On the go") {
    NavigationStack {
        NextView(mode: .onTheGo, onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Empty") {
    var snapshot = Fixtures.sampleSnapshot
    snapshot.actions = snapshot.actions.filter { $0.status.isClosed }
    return NavigationStack {
        NextView(mode: .full, onOpen: { _ in }, onQuickCapture: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: snapshot),
        snapshot: snapshot,
        today: { Fixtures.today }))
}

#Preview("At cap") {
    var snapshot = Fixtures.sampleSnapshot
    snapshot.actions.append(Action(
        id: NoteID(path: "Actions/One more thing.md"),
        title: "One more thing",
        status: .next,
        created: Fixtures.date(Fixtures.today, 9, 0),
        what: "Whatever pushes Next to the cap."))
    return NavigationStack {
        NextView(mode: .full, onOpen: { _ in }, onQuickCapture: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: snapshot),
        snapshot: snapshot,
        today: { Fixtures.today }))
}
#endif
