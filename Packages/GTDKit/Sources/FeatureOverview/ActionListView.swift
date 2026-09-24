#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// The ⌘F filter text of the enclosing window, so the shell's filter bar reaches the list it
/// filters. `""` when the list is used outside the Mac shell.
private struct OverviewQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var overviewQuery: String {
        get { self[OverviewQueryKey.self] }
        set { self[OverviewQueryKey.self] = newValue }
    }
}

extension View {
    /// Hands the window's ⌘F filter text to the lists below it.
    func overviewQuery(_ query: String) -> some View {
        environment(\.overviewQuery, query)
    }
}

/// Someday — the tier list no feature target owns (E3).
///
/// Grouped by area / project; context and time are **filters** (chips), never groupings.
///
/// On the Mac the list is a stock selectable `List`: a click or the arrow keys select a row,
/// the selection opens in the detail column (`onOpen`) and `selection` — the note that column
/// shows — is what the list highlights. The list keeps no selection of its own.
public struct ActionListView: View {
    private let status: ActionStatus
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.overviewQuery) private var query
    @State private var list: ActionListModel?

    public init(
        status: ActionStatus,
        selection: NoteID? = nil,
        onOpen: @escaping (NoteID) -> Void
    ) {
        self.status = status
        self.selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        Group {
            if let list {
                content(list)
            } else {
                Color.clear
            }
        }
        .task(id: status) {
            let fresh = ActionListModel(model: model, status: status)
            fresh.query = query
            list = fresh
        }
        .onChange(of: query) { _, newValue in
            list?.query = newValue
        }
    }

    @ViewBuilder private func content(_ list: ActionListModel) -> some View {
        VStack(spacing: 0) {
            filterChips(list)
            Divider()
            if list.isEmpty {
                emptyState(list)
            } else {
                selectableList {
                    ForEach(list.groups) { group in
                        if let title = group.title {
                            Section {
                                rows(group, list: list)
                            } header: {
                                Text(title).font(Typo.sectionHeader)
                            }
                        } else {
                            Section {
                                rows(group, list: list)
                            }
                        }
                    }
                }
            }
        }
    }

    /// macOS: `List(selection:)` — highlight, arrow keys and accessibility selection for free.
    /// iOS has no persistent row selection outside edit mode, so rows stay tap-to-open there.
    @ViewBuilder
    private func selectableList<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        #if os(macOS)
        List(selection: Binding<NoteID?>(
            get: { selection },
            set: { if let id = $0 { onOpen(id) } }),
            content: rows)
        #else
        List(content: rows)
        #endif
    }

    @ViewBuilder private func rows(_ group: ActionGroup, list: ActionListModel) -> some View {
        ForEach(group.actions) { action in
            ActionRow(
                action: action,
                projectTitle: group.title == nil ? nil : group.title,
                badges: list.badges(for: action),
                onComplete: { send(.complete(action.id)) })
                .contentShape(Rectangle())
                .tag(action.id)
                #if !os(macOS)
                .onTapGesture { onOpen(action.id) }
                #endif
                .accessibilityAddTraits(.isButton)
                .contextMenu {
                    Button(Copy.done) { send(.complete(action.id)) }
                    Divider()
                    ForEach(moveTargets, id: \.self) { target in
                        Button(Copy.status(target)) {
                            send(.setStatus(action.id, target, waiting: nil))
                        }
                    }
                }
        }
    }

    /// The statuses this list can move an item to — `waiting` needs who + follow-up (W1) and is
    /// therefore only reachable from the detail editor.
    private var moveTargets: [ActionStatus] {
        [.next, .someday].filter { $0 != status }
    }

    @ViewBuilder private func filterChips(_ list: ActionListModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(Copy.contextFilterHeader).font(Typo.meta).foregroundStyle(Color.textSecondary)
            ContextChipGroup(
                contexts: list.availableContexts,
                selection: Binding(get: { list.contexts }, set: { list.contexts = $0 }))
            Text(Copy.timeFilterHeader).font(Typo.meta).foregroundStyle(Color.textSecondary)
            TimeBucketChipGroup(selection: Binding(
                get: { list.timeAvailable.flatMap { TimeBucket(minutes: $0) } },
                set: { list.timeAvailable = $0?.minutes }))
            if list.isFiltered {
                HStack(spacing: Spacing.s) {
                    Text(OverviewCopy.matches(list.actions.count))
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                    Button(Copy.clearFilters) { list.clearFilters() }
                        .buttonStyle(.plain)
                        .font(Typo.meta)
                        .foregroundStyle(Color.gtdAccent)
                }
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder private func emptyState(_ list: ActionListModel) -> some View {
        if list.isFiltered {
            ContentUnavailableView(
                OverviewCopy.emptyFilterTitle,
                systemImage: OverviewSymbols.filter,
                description: Text(OverviewCopy.emptyFilterBody))
        } else {
            // This list only ever shows Someday (`ProjectsListView`/`WaitingView`/`NextView` own
            // their own tiers) — the canonical empty-state string (STYLEGUIDE §3.9, DesignSystem)
            // instead of the generic `OverviewCopy.emptyListTitle(_:)` this used to share with
            // every status.
            ContentUnavailableView(
                Copy.emptySomedayTitle,
                systemImage: Symbols.someday,
                description: Text(OverviewCopy.emptyListBody))
        }
    }

    private func send(_ command: GTDCommand) {
        Task { await model.perform(command) }
    }
}

#Preview("Someday") {
    ActionListView(status: .someday, onOpen: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}

#Preview("Someday · dark") {
    ActionListView(status: .someday, onOpen: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}
#endif
