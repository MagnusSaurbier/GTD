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

/// The Mac shell (E3, STYLEGUIDE §4.1): sidebar with live counts · list · note editor.
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
        NavigationSplitView {
            sidebar
        } content: {
            ContentColumn(navigation: nav)
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) { UndoOverlay() }
        .sheet(isPresented: processingBinding) {
            InboxProcessingView(onFinished: { nav.isProcessingInbox = false })
        }
        .sheet(isPresented: issuesBinding) {
            VaultIssuesView()
        }
        .onChange(of: model.snapshot) { _, snapshot in
            nav.prune(against: snapshot)
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
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
                description: Text(OverviewCopy.noSelectionBody))
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
    @Environment(AppModel.self) private var model
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
        .toolbar { toolbarContent }
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
            NextView(mode: .full, onOpen: { navigation.open(action: $0) })
        case .backlog:
            ActionListView(status: .backlog, onOpen: { navigation.open(action: $0) })
        case .maybe:
            ActionListView(status: .maybe, onOpen: { navigation.open(action: $0) })
        case .waiting:
            WaitingView(onOpen: { navigation.open(action: $0) })
        case .deferred:
            DeferredView(onOpen: { navigation.open(action: $0) })
        case .projects:
            ProjectsListView(
                onOpenProject: { navigation.open(project: $0) },
                onOpenAction: { navigation.open(action: $0) })
        case .routines:
            RoutinesHomeView()
        case .review:
            WeeklyReviewView(onFinished: { navigation.select(.next) })
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
                CalendarStrip(onOpen: { navigation.open(action: $0) })
                    .padding(.bottom, Spacing.s)
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if Rules.inboxQueue(model.snapshot).count > 0 {
            ToolbarItem(placement: .primaryAction) {
                InboxStartButton(action: { navigation.isProcessingInbox = true })
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(get: { navigation.query }, set: { navigation.query = $0 })
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
