#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// Waiting-for list (W2). **Owned by T23** — this is the compiling shell.
public struct WaitingView: View {
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(onOpen: @escaping (NoteID) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = WaitingListModel(model: model)
        Group {
            if list.waiting.isEmpty {
                ContentUnavailableView(Copy.emptyWaitingTitle, systemImage: Symbols.waiting)
            } else {
                List(list.waiting, id: \.id) { action in
                    ActionRow(action: action, badges: list.badges(for: action))
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(action.id) }
                }
            }
        }
        .navigationTitle(Copy.waiting)
    }
}

/// Deferred items grouped by return date (D1). **Owned by T23.**
public struct DeferredView: View {
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(onOpen: @escaping (NoteID) -> Void) {
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = WaitingListModel(model: model)
        List {
            Section("This week") {
                ForEach(list.deferredThisWeek, id: \.id) { row($0, list) }
            }
            Section("Later") {
                ForEach(list.deferredLater, id: \.id) { row($0, list) }
            }
        }
        .navigationTitle(Copy.deferLabel)
    }

    private func row(_ action: Action, _ list: WaitingListModel) -> some View {
        ActionRow(action: action, badges: list.badges(for: action))
            .contentShape(Rectangle())
            .onTapGesture { onOpen(action.id) }
    }
}

/// The Mac calendar strip (D3): 14 days, markers distinguished by symbol, not hue.
public struct CalendarStrip: View {
    private let days: Int
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(days: Int = 14, onOpen: @escaping (NoteID) -> Void) {
        self.days = days
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = WaitingListModel(model: model)
        HStack(spacing: Spacing.xs) {
            ForEach(Array(list.timeline(days: days).enumerated()), id: \.offset) { _, column in
                VStack(spacing: Spacing.xs) {
                    Text(DateText.short(column.day, today: list.today))
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(Array(column.entries.prefix(3).enumerated()), id: \.offset) { _, entry in
                        Button {
                            onOpen(entry.action)
                        } label: {
                            Image(systemName: symbol(entry.kind))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.m)
        .background(Color.surfaceCard, in: Radius.tileShape)
    }

    private func symbol(_ kind: Rules.TimelineKind) -> String {
        switch kind {
        case .deferred: Symbols.deferred
        case .due: Symbols.due
        case .followUp: Symbols.waiting
        }
    }
}

#Preview {
    NavigationStack {
        WaitingView(onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}
#endif
