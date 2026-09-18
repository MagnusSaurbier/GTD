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

/// The Mac shell's content router (E3). **Owned by T25** — this is the compiling shell.
public struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .next
    @State private var openAction: NoteID?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            let counts = Rules.sidebarCounts(model.snapshot, today: model.today())
            List(SidebarItem.allCases, id: \.self, selection: $selection) { item in
                HStack {
                    Label(item.title, systemImage: item.symbol)
                    Spacer()
                    if let count = item.count(counts) {
                        Text("\(count)").font(Typo.counter).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            content
        } detail: {
            if let openAction {
                ActionDetailView(action: openAction)
            } else {
                ContentUnavailableView(Copy.next, systemImage: Symbols.next)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch selection ?? .next {
        case .next: NextView(mode: .full, onOpen: { openAction = $0 })
        case .waiting: WaitingView(onOpen: { openAction = $0 })
        case .deferred: DeferredView(onOpen: { openAction = $0 })
        case .projects: ProjectsListView(onOpenProject: { _ in }, onOpenAction: { openAction = $0 })
        case .routines: RoutinesHomeView()
        case .review: WeeklyReviewView(onFinished: {})
        case .inbox: InboxProcessingView(onFinished: {})
        case .backlog: ActionListView(status: .backlog, onOpen: { openAction = $0 })
        case .maybe: ActionListView(status: .maybe, onOpen: { openAction = $0 })
        }
    }
}

/// Backlog / Maybe lists. **Owned by T25.**
public struct ActionListView: View {
    private let status: ActionStatus
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(status: ActionStatus, onOpen: @escaping (NoteID) -> Void) {
        self.status = status
        self.onOpen = onOpen
    }

    public var body: some View {
        let today = model.today()
        List(Rules.visibleActions(model.snapshot, today: today).filter { $0.status == status }, id: \.id) { action in
            ActionRow(
                action: action,
                projectTitle: action.project.flatMap { model.snapshot.project($0)?.title },
                badges: SignalPresentation.badges(
                    for: Rules.signals(for: action, today: today), today: today))
                .contentShape(Rectangle())
                .onTapGesture { onOpen(action.id) }
        }
        .navigationTitle(Copy.status(status))
    }
}

/// The note editor of the right-hand column (E3). **Owned by T25.**
public struct ActionDetailView: View {
    private let action: NoteID
    @Environment(AppModel.self) private var model

    public init(action: NoteID) {
        self.action = action
    }

    public var body: some View {
        Group {
            if let action = model.snapshot.action(action) {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(action.title).font(Typo.screenTitle)
                    Text(Copy.why).font(Typo.sectionHeader)
                    Text(action.why).font(Typo.body).foregroundStyle(Color.textSecondary)
                    Text(Copy.what).font(Typo.sectionHeader)
                    Text(action.what).font(Typo.body).foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .padding(Spacing.screenMargin)
            } else {
                ContentUnavailableView(Copy.next, systemImage: Symbols.next)
            }
        }
    }
}

#Preview {
    OverviewView()
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}
#endif
