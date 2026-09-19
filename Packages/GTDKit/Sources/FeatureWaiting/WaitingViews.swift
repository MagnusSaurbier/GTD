#if canImport(SwiftUI)
import SwiftUI
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures

/// Waiting-for list (W2): what · who · waiting since N days · follow-up, sorted by staleness.
/// Row actions: chase done → bump the follow-up, resolved → back to Next/Backlog or done, edit
/// who. **Owned by T23.**
///
/// On the Mac the list is a stock selectable `List` (M2, same as `ActionListView`): a click or
/// the arrow keys select a row, selecting opens it in the detail column (`onOpen`), and
/// `selection` — the note that column shows — is what the list highlights. The list keeps no
/// selection of its own. iOS keeps tap-to-open.
public struct WaitingView: View {
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model
    @State private var editingWho: Action?

    public init(selection: NoteID? = nil, onOpen: @escaping (NoteID) -> Void) {
        self.selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = WaitingListModel(model: model)
        Group {
            if list.waiting.isEmpty {
                ContentUnavailableView(Copy.emptyWaitingTitle, systemImage: Symbols.waiting)
            } else {
                SelectableList(selection: selection, onOpen: onOpen) {
                    ForEach(list.waiting) { action in
                        WaitingRow(action: action, list: list, onOpen: onOpen, onEditWho: { editingWho = $0 })
                            .tag(action.id)
                    }
                }
            }
        }
        .navigationTitle(Copy.waiting)
        .sheet(item: $editingWho) { action in
            WaitingInfoSheet(
                initial: list.waitingInfo(for: action),
                suggestedWho: list.recentWho,
                today: list.today
            ) { info in
                Task { await model.perform(.setStatus(action.id, .waiting, waiting: info)) }
            }
        }
    }
}

/// macOS: `List(selection:)` — highlight, arrow keys and accessibility selection for free, with
/// the detail column's note as the selected row. iOS has no persistent row selection outside
/// edit mode, so rows stay tap-to-open there. Mirrors `FeatureOverview.ActionListView` (M2).
private struct SelectableList<Rows: View>: View {
    let selection: NoteID?
    let onOpen: (NoteID) -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        #if os(macOS)
        List(selection: Binding<NoteID?>(
            get: { selection },
            set: { if let id = $0 { onOpen(id) } }),
            content: rows)
        #else
        List(content: rows)
        #endif
    }
}

/// One row of `WaitingView`. Not a `DesignSystem` component — the who/since/follow-up columns
/// are specific to the waiting list (STYLEGUIDE §1.4 "one row per concept" still holds:
/// `ActionRow`'s second line has no room for them).
private struct WaitingRow: View {
    let action: Action
    let list: WaitingListModel
    let onOpen: (NoteID) -> Void
    let onEditWho: (Action) -> Void
    @Environment(AppModel.self) private var model

    /// `true` while the row offers the "bump" chip: the follow-up chip shows the **suggested**
    /// +7 d date (dashed) instead of the current one, and nothing is written until the user
    /// confirms a date in its picker (§1 "no lying defaults").
    @State private var offeringBump = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                metaLine
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                badgeRow
                DateValueChip(
                    label: Copy.followUp,
                    value: followUpBinding,
                    suggestion: offeringBump ? list.suggestedBump : nil,
                    today: list.today,
                    signal: list.followUpSignal(for: action),
                    signalSymbol: Symbols.chase)
            }
        }
        .padding(.vertical, Spacing.rowVertical)
        .contentShape(Rectangle())
        #if !os(macOS)
        .onTapGesture { onOpen(action.id) }
        #endif
        .swipeActions(edge: .trailing) {
            Button {
                Task { await model.perform(.complete(action.id)) }
            } label: {
                Label(Copy.done, systemImage: Symbols.done)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await model.perform(.setStatus(action.id, .backlog, waiting: nil)) }
            } label: {
                Label(Copy.backlog, systemImage: Symbols.backlog)
            }
        }
        .contextMenu {
            Button {
                offeringBump = true
            } label: {
                Label("Bump follow-up", systemImage: Symbols.chase)
            }
            Button {
                Task { await model.perform(.setStatus(action.id, .next, waiting: nil)) }
            } label: {
                Label(Copy.next, systemImage: Symbols.next)
            }
            Button {
                Task { await model.perform(.setStatus(action.id, .backlog, waiting: nil)) }
            } label: {
                Label(Copy.backlog, systemImage: Symbols.backlog)
            }
            Button {
                Task { await model.perform(.complete(action.id)) }
            } label: {
                Label(Copy.done, systemImage: Symbols.done)
            }
            Button {
                onEditWho(action)
            } label: {
                Label("Edit who", systemImage: Symbols.waiting)
            }
        }
    }

    @ViewBuilder private var metaLine: some View {
        HStack(spacing: Spacing.xs) {
            if let who = action.waitingFor, !who.isEmpty {
                Text(who)
            }
            Text(DateText.age(days: list.waitingSinceDays(action)))
        }
        .font(Typo.meta)
        .foregroundStyle(Color.textSecondary)
    }

    @ViewBuilder private var badgeRow: some View {
        let badges = list.badges(for: action)
        if !badges.isEmpty {
            HStack(spacing: Spacing.xs) {
                ForEach(Array(badges.enumerated()), id: \.offset) { Badge($0.element) }
            }
        }
    }

    /// The follow-up chip's binding. While `offeringBump`, the chip reads as unset (so the
    /// suggested +7 d shows dashed); picking any date in its calendar confirms the bump.
    private var followUpBinding: Binding<Day?> {
        Binding(
            get: { offeringBump ? nil : action.followUpDate },
            set: { newValue in
                offeringBump = false
                guard let newValue, let info = list.bumped(action, to: newValue) else { return }
                Task { await model.perform(.setStatus(action.id, .waiting, waiting: info)) }
            })
    }

    private var accessibilityLabel: String {
        var parts = [action.title]
        if let who = action.waitingFor, !who.isEmpty { parts.append("waiting on \(who)") }
        parts.append(DateText.spelledAge(days: list.waitingSinceDays(action)))
        if let followUp = action.followUpDate {
            parts.append("follow up \(DateText.spelled(followUp, today: list.today))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Deferred items grouped by return date (D1): this week, then later. Actions: un-defer now,
/// change date. **Owned by T23.**
///
/// Selection behaves exactly as in `WaitingView` (M2). The screen is titled "Deferred", the name
/// the sidebar and the empty detail column use — `Copy.deferLabel` ("Defer") is the date chip's
/// field label, and naming the screen with it made the window title disagree with the sidebar.
public struct DeferredView: View {
    private let selection: NoteID?
    private let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    public init(selection: NoteID? = nil, onOpen: @escaping (NoteID) -> Void) {
        self.selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        let list = WaitingListModel(model: model)
        Group {
            if list.deferredThisWeek.isEmpty && list.deferredLater.isEmpty {
                ContentUnavailableView(WaitingCopy.deferredTitle, systemImage: Symbols.deferred)
            } else {
                SelectableList(selection: selection, onOpen: onOpen) {
                    if !list.deferredThisWeek.isEmpty {
                        Section("This week") {
                            ForEach(list.deferredThisWeek) {
                                DeferredRow(action: $0, list: list, onOpen: onOpen).tag($0.id)
                            }
                        }
                    }
                    if !list.deferredLater.isEmpty {
                        Section("Later") {
                            ForEach(list.deferredLater) {
                                DeferredRow(action: $0, list: list, onOpen: onOpen).tag($0.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(WaitingCopy.deferredTitle)
    }
}

private struct DeferredRow: View {
    let action: Action
    let list: WaitingListModel
    let onOpen: (NoteID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(action.title)
                    .font(Typo.body)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                badgeRow
            }
            Spacer(minLength: Spacing.s)
            DateValueChip(label: Copy.deferLabel, value: deferBinding, today: list.today)
        }
        .padding(.vertical, Spacing.rowVertical)
        .contentShape(Rectangle())
        #if !os(macOS)
        .onTapGesture { onOpen(action.id) }
        #endif
        .swipeActions(edge: .trailing) {
            Button {
                Task { await model.perform(.updateAction(list.unDeferred(action))) }
            } label: {
                Label("Un-defer now", systemImage: Symbols.deferred)
            }
        }
        .contextMenu {
            Button {
                Task { await model.perform(.updateAction(list.unDeferred(action))) }
            } label: {
                Label("Un-defer now", systemImage: Symbols.deferred)
            }
        }
    }

    @ViewBuilder private var badgeRow: some View {
        let badges = list.badges(for: action)
        if !badges.isEmpty {
            HStack(spacing: Spacing.xs) {
                ForEach(Array(badges.enumerated()), id: \.offset) { Badge($0.element) }
            }
        }
    }

    private var deferBinding: Binding<Day?> {
        Binding(
            get: { action.deferDate },
            set: { newValue in
                Task { await model.perform(.updateAction(list.redeferred(action, to: newValue))) }
            })
    }
}

/// The Mac calendar strip (D3): a 14-day strip anchored on today, up to 3 markers per day
/// distinguished by symbol, a signal colour only where STYLEGUIDE §2.2 defines one, an accent
/// underline on today, and overdue items piled on the leading edge. **Owned by T23.**
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
        HStack(alignment: .top, spacing: Spacing.xs) {
            overdueColumn(list)
            ForEach(Array(list.timeline(days: days).enumerated()), id: \.offset) { _, column in
                dayColumn(list, day: column.day, entries: column.entries, isToday: column.day == list.today)
            }
        }
        .padding(Spacing.m)
        .background(Color.surfaceCard, in: Radius.tileShape)
    }

    @ViewBuilder
    private func overdueColumn(_ list: WaitingListModel) -> some View {
        let entries = list.overduePile
        if !entries.isEmpty {
            VStack(spacing: Spacing.xs) {
                Text("Overdue")
                    .font(Typo.counter)
                    .foregroundStyle(Color.signal(.overdue))
                ForEach(Array(entries.prefix(3).enumerated()), id: \.offset) { _, entry in
                    marker(list, entry)
                }
                if entries.count > 3 {
                    Text("+\(entries.count - 3)")
                        .font(Typo.counter)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            Divider()
        }
    }

    @ViewBuilder
    private func dayColumn(_ list: WaitingListModel, day: Day, entries: [Rules.TimelineEntry], isToday: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(DateText.short(day, today: list.today))
                .font(Typo.counter)
                .foregroundStyle(isToday ? Color.ink : Color.textSecondary)
            ForEach(Array(entries.prefix(3).enumerated()), id: \.offset) { _, entry in
                marker(list, entry)
            }
            if entries.count > 3 {
                Text("+\(entries.count - 3)")
                    .font(Typo.counter)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if isToday {
                Rectangle().fill(Color.gtdAccent).frame(height: 2)
            }
        }
    }

    private func marker(_ list: WaitingListModel, _ entry: Rules.TimelineEntry) -> some View {
        Button {
            onOpen(entry.action)
        } label: {
            Image(systemName: symbol(entry.kind))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(markerColor(list.signalStep(for: entry)))
        }
        .buttonStyle(.plain)
        .help(entry.title)
        .accessibilityLabel(entry.title)
    }

    private func symbol(_ kind: Rules.TimelineKind) -> String {
        switch kind {
        case .deferred: Symbols.deferred
        case .due: Symbols.due
        case .followUp: Symbols.waiting
        }
    }

    /// Maps the semantic `SignalStep` to the presentation colour formula (STYLEGUIDE §2.1).
    /// `nil` (no signal applies) stays `textSecondary` — plain, untinted.
    private func markerColor(_ step: SignalStep?) -> Color {
        switch step {
        case nil: .textSecondary
        case .neutral: .signal(.neutral)
        case .aging: .signal(.aging)
        case .attention: .signal(.attention)
        case .overdue: .signal(.overdue)
        }
    }
}

#Preview("Waiting") {
    NavigationStack {
        WaitingView(onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Waiting — empty") {
    NavigationStack {
        WaitingView(onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: .empty),
        snapshot: .empty,
        today: { Fixtures.today }))
}

#Preview("Deferred") {
    NavigationStack {
        DeferredView(onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Deferred — empty") {
    NavigationStack {
        DeferredView(onOpen: { _ in })
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: .empty),
        snapshot: .empty,
        today: { Fixtures.today }))
}

#Preview("Calendar strip") {
    CalendarStrip(onOpen: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .padding()
}

#Preview("Calendar strip — empty") {
    CalendarStrip(onOpen: { _ in })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: .empty),
            snapshot: .empty,
            today: { Fixtures.today }))
        .padding()
}
#endif
