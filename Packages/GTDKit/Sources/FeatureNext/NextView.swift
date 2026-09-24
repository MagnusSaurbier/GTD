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
    /// The action the host currently shows in its detail column — its row is highlighted (M2).
    /// `nil` (the default) when the host has no detail column (iPhone) or does not say; the list
    /// then still highlights the row it opened last on the Mac.
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void
    /// Quick add (Mac `⌘N`, iPhone toolbar button): capture to inbox and jump into processing
    /// of that one card (I7). `FeatureNext` never imports `FeatureInbox`, so the app shell
    /// supplies this. `nil` hides the button (e.g. a host that has nowhere to route it yet).
    private let onQuickCapture: (() -> Void)?
    @Environment(AppModel.self) private var model

    public init(
        mode: NextViewMode,
        selection: NoteID? = nil,
        onOpen: @escaping (NoteID) -> Void,
        onQuickCapture: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.selection = selection
        self.onOpen = onOpen
        self.onQuickCapture = onQuickCapture
    }

    public var body: some View {
        NextListContent(
            model: model, mode: mode, selection: selection, onOpen: onOpen, onQuickCapture: onQuickCapture)
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
    /// What the host says is open (`NextView.selection`).
    let hostSelection: NoteID?
    let onOpen: (NoteID) -> Void
    let onQuickCapture: (() -> Void)?
    @State private var list: NextListModel
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// R-2 — the app coming to the foreground re-arms the `Next is full` sheet if Next is still
    /// over the cap (`NextListModel.enteredForeground()`).
    @Environment(\.scenePhase) private var scenePhase

    @State private var toastLabel: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var waitingSheetAction: Action?
    @State private var deferSheetAction: Action?
    /// R-2 — set (and `NextListModel.capSheetShown()` called) the moment `list.showsCapSheet`
    /// turns true, so the sheet stays presented for the rest of this foreground even though
    /// `showsCapSheet` itself goes false the instant it is "shown" (that flag means "still owed",
    /// not "currently visible").
    @State private var isCapSheetPresented = false
    /// A row command the reducer refused. Never swallowed with `try?` — every row action goes
    /// through `run(_:)`, which lands the failure here so it reaches the person instead of
    /// disappearing silently.
    @State private var errorMessage: String?
    /// The highlighted row. Follows `hostSelection` whenever the host changes it; a click or an
    /// arrow key moves it directly, so a host that never passes `selection` still gets a
    /// highlight.
    @State private var selectedID: NoteID?

    init(
        model: AppModel,
        mode: NextViewMode,
        selection: NoteID?,
        onOpen: @escaping (NoteID) -> Void,
        onQuickCapture: (() -> Void)?
    ) {
        self.hostSelection = selection
        self.onOpen = onOpen
        self.onQuickCapture = onQuickCapture
        _selectedID = State(initialValue: selection)
        _list = State(initialValue: NextListModel(model: model, mode: mode))
    }

    var body: some View {
        // The list is the screen's top-level scroll view and the chips ride in its top safe-area
        // bar, under the pinned headline (#33) — neither moves when the list scrolls.
        Group {
            if list.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listView
            }
        }
        #if os(iOS)
        .safeAreaBar(edge: .top, spacing: 0) { filterBar }
        #else
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        #endif
        .pinnedScreenTitle(Copy.next)
        .toolbar { quickCaptureToolbar }
        .onChange(of: hostSelection) { _, newValue in selectedID = newValue }
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
        .sheet(isPresented: $isCapSheetPresented) {
            NextCapSheet(list: list) { action in
                run { try await list.demoteToSomeday(action) }
            }
        }
        .onChange(of: list.showsCapSheet, initial: true) { _, showsCapSheet in
            guard showsCapSheet else { return }
            isCapSheetPresented = true
            list.capSheetShown()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { list.enteredForeground() }
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
        // R-3 — a row action that tries to move something into Next without what it needs names
        // the gap instead of failing silently (deliverable 1: "surfaces to the shell's alert").
        case let GTDError.missingFields(fields): Copy.missingFields(fields)
        default: Copy.actionFailed
        }
    }

    // MARK: - Filter bar (E1)

    private var filterBar: some View {
        VStack(spacing: 0) {
            filterChips
            Divider()
        }
    }

    /// Mac: contexts and time on two rows that wrap (`FlowLayout`) — a one-line scroller cut the
    /// time chips off at the default column width with no hint that there was more (M7).
    /// iPhone: one horizontally scrolling line, to keep the pinned bar as short as possible.
    @ViewBuilder private var filterChips: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: Spacing.s) {
            filterHeader(Copy.contextFilterHeader)
            HStack(alignment: .top, spacing: Spacing.s) {
                onlyMobileChip
                contextChips
            }
            filterHeader(Copy.timeFilterHeader)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                TimeBucketChipGroup(selection: timeBucketBinding)
                clearFiltersButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.s)
        #else
        VStack(alignment: .leading, spacing: Spacing.s) {
            filterHeader(Copy.contextFilterHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    onlyMobileChip
                    contextChips
                }
                .padding(.horizontal, Spacing.screenMargin)
            }
            filterHeader(Copy.timeFilterHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.l) {
                    TimeBucketChipGroup(selection: timeBucketBinding)
                    clearFiltersButton
                }
                .padding(.horizontal, Spacing.screenMargin)
            }
        }
        .padding(.vertical, Spacing.s)
        #endif
    }

    /// The caption over each chip group — same look as Someday's (`ActionListView`).
    private func filterHeader(_ text: String) -> some View {
        Text(text)
            .font(Typo.meta)
            .foregroundStyle(Color.textSecondary)
            #if !os(macOS)
            .padding(.horizontal, Spacing.screenMargin)
            #endif
    }

    private var contextChips: some View {
        ContextChipGroup(
            contexts: list.availableContexts,
            selection: Binding(get: { list.contexts }, set: { list.setContexts($0) }))
    }

    /// E2 — on the iPhone the list shows only on-the-go contexts while this chip is on (the
    /// default); switched off, every context's chip appears and the list is the whole Next list.
    /// Not a filter, so `Clear filters` leaves it alone. Absent in `.full`, which never restricts.
    @ViewBuilder private var onlyMobileChip: some View {
        if list.mode == .onTheGo {
            Chip(Copy.onlyMobile, state: list.isOnTheGoOnly ? .confirmed : .unset) {
                list.setShowsAllContexts(!list.showsAllContexts)
            }
        }
    }

    @ViewBuilder private var clearFiltersButton: some View {
        if list.isFiltered {
            Button(Copy.clearFilters) { list.clearFilters() }
                .font(Typo.chip)
                .foregroundStyle(Color.textSecondary)
                .buttonStyle(.plain)
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
        rows
            .animation(Motion.standard(reduceMotion: reduceMotion), value: list.items.map(\.id))
            .animation(Motion.standard(reduceMotion: reduceMotion), value: list.chase.map(\.id))
    }

    /// Mac: a stock `List(selection:)` (STYLEGUIDE §3.3 — system selection colour). Click
    /// anywhere on a row or move with the arrow keys → the row is selected, and selecting *is*
    /// opening (M2). `ForEach(id: \.id)` tags every row with its `NoteID`.
    /// iPhone: no persistent selection — rows are buttons that push the detail.
    @ViewBuilder private var rows: some View {
        #if os(macOS)
        List(selection: Binding(
            get: { selectedID },
            set: { newValue in
                selectedID = newValue
                if let newValue { onOpen(newValue) }
            })
        ) { sections }
        #else
        List { sections }
        #endif
    }

    @ViewBuilder private var sections: some View {
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

    /// `Next · 14/15` — never a bare number (P13). STYLEGUIDE §2.2: plain text below the cap, an
    /// attention badge `15/15` at the cap, overdue styling above it. Never a meter. When the
    /// list shows fewer rows than that count, the trailing text says so (`8 of 14 on the go`).
    private var capHeader: some View {
        WholePointHeight { capHeaderContent }
    }

    private var capHeaderContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let badge = list.capBadge {
                Text(Copy.next)
                Badge(badge).fixedSize()
            } else {
                Text(list.capHeaderText)
            }
            Spacer(minLength: Spacing.s)
            if let visible = list.visibleCountText {
                Text(visible)
            }
        }
        .font(Typo.counter)
        .foregroundStyle(Color.textSecondary)
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.capHeaderSpokenText)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Rows

    @ViewBuilder private func nextRow(_ action: Action) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            row(action) { run { try await list.complete(action) } }
            if list.showsChecklist(action) {
                checklist(for: action)
            }
        }
        .nextRowChrome()
        .draggableNote(action.id)
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(Copy.done) { run { try await list.complete(action) } }
                .tint(Color.signalDone)
        }
        .swipeActions(edge: .leading) {
            Button("\(Copy.demote) to \(Copy.someday)") {
                run { try await list.demoteToSomeday(action) }
            }
            .tint(Color.fillQuiet)
        }
        #endif
        .contextMenu {
            // Every swipe action needs a non-swipe route: the Mac has no swipes at all, and
            // VoiceOver reaches the menu but not a gesture (STYLEGUIDE §8).
            Button(Copy.done) { run { try await list.complete(action) } }
            if action.status != .inProgress {
                Button(Copy.start) { run { try await list.start(action) } }
            }
            Button("\(Copy.demote) to \(Copy.someday)") {
                run { try await list.demoteToSomeday(action) }
            }
            Button(Copy.waiting) { waitingSheetAction = action }
            Button(Copy.deferLabel) { deferSheetAction = action }
            // The drag-to-section twin (E3) — where the screen has sections to move to.
            MoveToMenu(id: action.id)
        }
    }

    @ViewBuilder private func chaseRow(_ action: Action) -> some View {
        row(
            action, title: list.chaseTitle(for: action), spokenLabel: list.chaseSpokenLabel(for: action)
        ) { run { try await list.resolveChase(action) } }
            .nextRowChrome()
            .draggableNote(action.id)
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
                MoveToMenu(id: action.id)
            }
    }

    private func row(
        _ action: Action,
        title: String? = nil,
        spokenLabel: String? = nil,
        onComplete: @escaping () -> Void
    ) -> NextRow {
        NextRow(
            action: action,
            title: title ?? action.title,
            metaParts: list.metaParts(for: action),
            badges: list.badges(for: action),
            spokenLabel: spokenLabel ?? list.spokenLabel(for: action),
            onOpen: {
                selectedID = action.id
                onOpen(action.id)
            },
            onComplete: onComplete)
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
        .padding(.leading, NextRow.separatorInset)
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

private extension View {
    /// What every Next/chase row shares with the `List` around it: the separator starts where
    /// the row's text starts, for every row alike, and the row is a whole number of points tall.
    func nextRowChrome() -> some View {
        // `NextRow.separatorInset` is read once, here, on the main actor: the closure below is
        // `@Sendable` (`.alignmentGuide`'s parameter type), and reading a static member of a
        // `View`-conforming type from inside it warned ("main actor-isolated static property
        // referenced from a Sendable closure"). Capturing the already-read value sidesteps the
        // cross-isolation access instead of silencing the check.
        let inset = NextRow.separatorInset
        return WholePointHeight { self }
            .alignmentGuide(.listRowSeparatorLeading) { _ in inset }
    }
}

/// Rounds its content's height up to a whole point.
///
/// Text and scaled badge metrics give rows heights like 89.67 pt. The iOS list stacks its cells
/// at those fractional offsets and then snaps each one to the pixel grid on its own, which now
/// and then leaves a 1 px gap between two cells — the grouped background shows through as a
/// stray full-width hairline (walkthrough P14). Whole-point rows and headers cannot drift.
private struct WholePointHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// R-2's `Next is full` sheet: a deferred item returned into an already-full Next. Lists the
/// current Next items with a `Demote` button each, and `Cancel` — the same shape as the inbox's
/// cap sheet (STYLEGUIDE §3.6), reimplemented locally because `FeatureNext` does not import
/// `FeatureInbox` (ARCHITECTURE §2: features depend only on `GTDAppCore` + `DesignSystem`).
/// **No "send to Someday instead" shortcut** — STYLEGUIDE §3.6 is explicit that a cap refusal
/// offers demote-or-cancel only, never an automatic reroute.
private struct NextCapSheet: View {
    let list: NextListModel
    let onDemote: (Action) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Copy.capSheetBody)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(list.items, id: \.id) { action in
                    HStack {
                        ActionRow(action: action, projectTitle: list.projectTitle(for: action))
                        Spacer(minLength: Spacing.s)
                        Button(Copy.demote) {
                            onDemote(action)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .scrollingSheetFrame()
            .navigationTitle(Copy.capSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.cancel) { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
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
