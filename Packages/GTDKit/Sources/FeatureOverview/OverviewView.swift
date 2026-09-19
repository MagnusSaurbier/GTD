#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import FeatureInbox
import FeatureNext
import FeatureProjects
import FeatureWaiting
import FeatureRoutines
import FeatureSettings
import FeatureReview
import GTDFixtures

/// The Mac shell (E3, STYLEGUIDE §4.1): sidebar with live counts · list · note editor. The
/// guided flows (weekly review, routines) have no list/detail pair and get sidebar + one wide
/// column instead (`SidebarItem.spansDetailColumn`).
///
/// It owns no GTD semantics and no list rendering of its own beyond the generic
/// `ActionListView`: every section routes to the feature that owns it.
public struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var ownedNavigation = OverviewNavigation()
    private let injectedNavigation: OverviewNavigation?

    public init() {
        injectedNavigation = nil
    }

    /// Used by the app shell (T40) when it also installs `OverviewCommands` in the menu bar,
    /// so window and menu share one selection.
    public init(navigation: OverviewNavigation) {
        injectedNavigation = navigation
    }

    private var nav: OverviewNavigation { injectedNavigation ?? ownedNavigation }

    public var body: some View {
        Group {
            if nav.selection.spansDetailColumn {
                NavigationSplitView {
                    sidebar
                } detail: {
                    FlowColumn(navigation: nav)
                }
            } else {
                NavigationSplitView {
                    sidebar
                } content: {
                    ContentColumn(navigation: nav)
                        .navigationSplitViewColumnWidth(
                            min: OverviewLayout.listMinWidth, ideal: OverviewLayout.listIdealWidth)
                } detail: {
                    detail
                        .navigationSplitViewColumnWidth(
                            min: OverviewLayout.detailMinWidth,
                            ideal: OverviewLayout.detailIdealWidth)
                }
            }
        }
        .overlay(alignment: .bottom) { UndoOverlay() }
        // The `NavigationStack` renders `InboxProcessingView`'s toolbar — counter, `⌘Z` and
        // `Done`. Without it the sheet has no way out (T41); the previews had one, the app did not.
        .sheet(isPresented: processingBinding) {
            NavigationStack {
                InboxProcessingView(onFinished: { nav.isProcessingInbox = false })
            }
        }
        // A Mac sheet with no control that closes it is a trap: `VaultIssuesView` brings only a
        // `.navigationTitle`, so the way out is added here, as the iPhone shell already did (T41).
        .sheet(isPresented: issuesBinding) {
            NavigationStack {
                VaultIssuesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Copy.done) { nav.isIssuesPresented = false }
                        }
                    }
            }
        }
        .onChange(of: model.snapshot) { _, snapshot in
            nav.apply(snapshot: snapshot, renames: model.renames)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        let counts = Rules.sidebarCounts(model.snapshot, today: model.today())
        return List(selection: selectionBinding) {
            Section {
                ForEach(SidebarItem.counted, id: \.self) { item in
                    SidebarRow(
                        item: item,
                        count: item.count(counts),
                        capSignal: item == .next ? Rules.capSignal(model.snapshot) : nil,
                        today: model.today())
                        .tag(item)
                }
            }
            Section {
                ForEach(SidebarItem.flows, id: \.self) { item in
                    SidebarRow(item: item, count: nil, capSignal: nil, today: model.today())
                        .tag(item)
                }
            }
            if !model.snapshot.issues.isEmpty {
                Section {
                    Button {
                        nav.isIssuesPresented = true
                    } label: {
                        HStack {
                            Label(OverviewCopy.vaultIssues, systemImage: OverviewSymbols.issues)
                            Spacer(minLength: Spacing.s)
                            Text("\(model.snapshot.issues.count)")
                                .font(Typo.counter)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: OverviewLayout.sidebarMinWidth,
            ideal: OverviewLayout.sidebarIdealWidth,
            max: OverviewLayout.sidebarMaxWidth)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch nav.detail {
        case let .action(id):
            ActionDetailView(action: id)
        case let .project(id):
            ProjectDetailView(project: id, onOpenAction: { nav.open(action: $0) })
        case nil:
            ContentUnavailableView(
                OverviewCopy.noSelectionTitle,
                systemImage: OverviewSymbols.placeholder,
                description: Text(nav.selection.emptyDetailBody ?? ""))
        }
    }

    // MARK: - Bindings

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { nav.selection },
            set: { newValue in
                if let newValue { nav.select(newValue) }
            })
    }

    private var processingBinding: Binding<Bool> {
        Binding(get: { nav.isProcessingInbox }, set: { nav.isProcessingInbox = $0 })
    }

    private var issuesBinding: Binding<Bool> {
        Binding(get: { nav.isIssuesPresented }, set: { nav.isIssuesPresented = $0 })
    }
}

/// One sidebar row: name, symbol and its live count. The count turns into a `Badge` when the
/// section carries a signal (STYLEGUIDE §4.1 — currently only Next at its cap).
private struct SidebarRow: View {
    let item: SidebarItem
    let count: Int?
    let capSignal: Signal?
    let today: Day

    var body: some View {
        HStack {
            Label(item.title, systemImage: item.symbol)
            Spacer(minLength: Spacing.s)
            if let badge = capBadge {
                Badge(badge)
            } else if let count, count > 0 {
                Text("\(count)")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("\(count)")
            }
        }
    }

    private var capBadge: BadgeContent? {
        capSignal.map { SignalPresentation.badge(for: $0, today: today) }
    }
}

/// The middle column: the owning feature's list, the ⌘F filter bar and the docked calendar
/// strip (D3).
private struct ContentColumn: View {
    let navigation: OverviewNavigation
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isFilterVisible {
                filterBar
                Divider()
            }
            list
                .overviewQuery(navigation.query)
            if navigation.selection.showsCalendarStrip {
                Divider()
                calendarDock
            }
        }
        .navigationTitle(navigation.selection.title)
        .background {
            Button(OverviewCopy.filter) { navigation.beginSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onChange(of: navigation.isSearching) { _, searching in
            filterFocused = searching
        }
    }

    // MARK: Routing

    @ViewBuilder private var list: some View {
        switch navigation.selection {
        case .inbox:
            InboxRawList(navigation: navigation)
        case .next:
            NextView(
                mode: .full, selection: navigation.openAction,
                onOpen: { navigation.open(action: $0) })
        case .backlog:
            ActionListView(
                status: .backlog, selection: navigation.openAction,
                onOpen: { navigation.open(action: $0) })
        case .maybe:
            ActionListView(
                status: .maybe, selection: navigation.openAction,
                onOpen: { navigation.open(action: $0) })
        case .waiting:
            WaitingView(
                selection: navigation.openAction,
                onOpen: { navigation.open(action: $0) })
        case .deferred:
            DeferredView(
                selection: navigation.openAction,
                onOpen: { navigation.open(action: $0) })
        case .projects:
            ProjectsListView(
                selection: navigation.openProject,
                onOpenProject: { navigation.open(project: $0) },
                onOpenAction: { navigation.open(action: $0) })
        case .routines, .review:
            // Never reached: these sections render in `FlowColumn`, across content + detail.
            EmptyView()
        }
    }

    // MARK: Chrome

    private var isFilterVisible: Bool {
        navigation.isSearching || !navigation.query.isEmpty
    }

    private var filterBar: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: OverviewSymbols.filter)
                .foregroundStyle(Color.textSecondary)
            TextField(OverviewCopy.filterPlaceholder, text: queryBinding)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .focused($filterFocused)
            if !navigation.query.isEmpty {
                Button(Copy.clearFilters) { navigation.endSearch() }
                    .buttonStyle(.plain)
                    .font(Typo.meta)
                    .foregroundStyle(Color.gtdAccent)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder private var calendarDock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                navigation.isCalendarExpanded.toggle()
            } label: {
                HStack(spacing: Spacing.s) {
                    Label(OverviewCopy.calendar, systemImage: OverviewSymbols.calendar)
                        .font(Typo.meta)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Image(systemName: navigation.isCalendarExpanded
                        ? OverviewSymbols.collapse : OverviewSymbols.expand)
                        .foregroundStyle(Color.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.s)

            if navigation.isCalendarExpanded {
                OverviewCalendarStrip(onOpen: { navigation.open(action: $0) })
                    .padding(.bottom, Spacing.s)
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { navigation.query }, set: { navigation.query = $0 })
    }
}

/// The guided flows (weekly review, routines): one wide column next to the sidebar. In the list
/// column the review wizard was ~130 pt wide, next to a detail pane with nothing to show.
private struct FlowColumn: View {
    let navigation: OverviewNavigation

    var body: some View {
        Group {
            switch navigation.selection {
            case .routines:
                RoutinesHomeView()
            case .review:
                WeeklyReviewView(onFinished: { navigation.select(.next) })
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(navigation.selection.title)
    }
}

/// The inbox section: raw captures, read-only — processing order is forced (I1), so the only
/// way in is the *Process inbox* button.
private struct InboxRawList: View {
    let navigation: OverviewNavigation
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = model.today()
        let items = Rules.inboxQueue(model.snapshot)
        Group {
            if items.isEmpty {
                ContentUnavailableView(Copy.emptyInboxTitle, systemImage: Symbols.inbox)
            } else {
                List {
                    // Labelled and prominent, where the captures are — as a toolbar item it was
                    // an unlabelled icon identical to the sidebar's Inbox icon. `⌘I` stays in
                    // the menu bar (`OverviewCommands`).
                    InboxStartButton(action: { navigation.isProcessingInbox = true })
                        .buttonStyle(.borderedProminent)
                        .labelStyle(.titleAndIcon)
                        .controlSize(.large)
                        .tint(Color.gtdAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.s)
                        .listRowSeparator(.hidden)
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            Text(item.text)
                                .font(Typo.body)
                                .foregroundStyle(Color.ink)
                                .lineLimit(3)
                            Spacer(minLength: Spacing.s)
                            ForEach(
                                Array(SignalPresentation.badges(
                                    for: Rules.signals(for: item, today: today),
                                    today: today).enumerated()),
                                id: \.offset
                            ) { badge in
                                Badge(badge.element)
                            }
                        }
                        .padding(.vertical, Spacing.rowVertical)
                    }
                }
            }
        }
    }
}

/// N6 — the undo toast, bottom-anchored, one at a time (STYLEGUIDE §3.8).
private struct UndoOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?

    var body: some View {
        Group {
            if let shown {
                UndoToast(label: shown, onUndo: { Task { await model.undo() } })
                    .padding(.bottom, Spacing.l)
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: shown)
        .task(id: model.undoLabel) {
            shown = model.undoLabel
            guard shown != nil else { return }
            try? await Task.sleep(for: .seconds(MotionTiming.toastDuration))
            shown = nil
        }
    }
}

#Preview("Overview") {
    OverviewView()
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}

#Preview("Overview · AX1") {
    OverviewView()
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .dynamicTypeSize(.accessibility1)
}

#Preview("Overview · dark") {
    OverviewView()
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}
#endif
