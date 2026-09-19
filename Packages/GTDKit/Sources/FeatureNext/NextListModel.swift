import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Which Next list this is (N5): the Mac's full list, or the iPhone's on-the-go list.
public enum NextViewMode: String, Sendable, Equatable, Hashable, CaseIterable, CustomStringConvertible {
    case full
    /// iPhone: hard-filtered to `config.onTheGoContexts`; the filter cannot be removed (E2).
    case onTheGo

    public var description: String { rawValue }
}

/// Filtering, sections, ordering and row actions for the Next view (E1). Plain and
/// unit-testable — **no SwiftUI**. Owned by T21.
@MainActor
@Observable
public final class NextListModel {
    public let mode: NextViewMode

    /// Context filter chips; empty = no context filter (never a default selection). Mutate
    /// through `setContexts`/`toggleContext` — persisted per device the moment they change.
    public private(set) var contexts: [String]
    /// Time available in minutes; `nil` = no time filter. Mutate through `setTimeAvailable`.
    public private(set) var timeAvailable: Int?

    private let model: AppModel
    private let store: any NextFilterStore

    public init(model: AppModel, mode: NextViewMode, store: any NextFilterStore = UserDefaultsNextFilterStore()) {
        self.model = model
        self.mode = mode
        self.store = store
        self.contexts = store.contexts(for: mode)
        self.timeAvailable = store.timeAvailable(for: mode)
    }

    public var today: Day { model.today() }

    // MARK: - Filters (E1)

    /// Contexts the chips may offer — on-the-go mode narrows the set, and that narrowing
    /// cannot be lifted from the UI (E2).
    public var availableContexts: [String] {
        mode == .onTheGo ? model.snapshot.config.onTheGoContexts : model.snapshot.config.contexts
    }

    public var isFiltered: Bool { !contexts.isEmpty || timeAvailable != nil }

    public func setContexts(_ contexts: [String]) {
        self.contexts = contexts
        persist()
    }

    public func toggleContext(_ context: String) {
        if let index = contexts.firstIndex(of: context) {
            contexts.remove(at: index)
        } else {
            contexts.append(context)
        }
        persist()
    }

    public func setTimeAvailable(_ minutes: Int?) {
        timeAvailable = minutes
        persist()
    }

    public func clearFilters() {
        contexts = []
        timeAvailable = nil
        persist()
    }

    private func persist() {
        store.save(contexts: contexts, timeAvailable: timeAvailable, for: mode)
    }

    // MARK: - Lists

    /// Chase items (W2) — their own section above Next, unaffected by the context/time filters:
    /// chasing someone is never about what fits your current context.
    public var chase: [Action] { Rules.chaseItems(model.snapshot, today: today) }

    /// The Next list itself: in-progress pinned on top, then Next.
    public var items: [Action] {
        switch mode {
        case .full:
            Rules.nextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        case .onTheGo:
            Rules.onTheGoNextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        }
    }

    /// True once both sections are empty — the only time the big empty state replaces the list.
    public var isEmpty: Bool { items.isEmpty && chase.isEmpty }

    public var emptyStateTitle: String { isFiltered ? Copy.emptyNextFilteredTitle : Copy.emptyNextTitle }
    public var emptyStateBody: String { isFiltered ? Copy.emptyNextFilteredBody : Copy.emptyNextBody }

    // MARK: - Cap (STYLEGUIDE §2.2)

    /// How many actions occupy a Next slot right now — independent of the view's own filters.
    public var capCount: Int { Rules.countsTowardCap(model.snapshot) }

    /// `nil` below the cap (render `capCount` as a plain number); `15/15` at the cap; overdue
    /// styling above it. Never a meter/progress component.
    public var capBadge: BadgeContent? {
        Rules.capSignal(model.snapshot).map { SignalPresentation.badge(for: $0, today: today) }
    }

    /// The cap the count is measured against (`config.nextCap`).
    public var capLimit: Int { model.snapshot.config.nextCap }

    /// The Next section's header label — `Next · 14/15`. Never a bare number: a count without
    /// its label and its limit says nothing (walkthrough P13). At/above the cap the view shows
    /// `Copy.next` plus `capBadge` instead, which carries the same `15/15`.
    public var capHeaderText: String { "\(Copy.next) · \(capCount)/\(capLimit)" }

    /// VoiceOver wording for the header — the `·` and `/` are not spoken as symbols.
    public var capHeaderSpokenText: String {
        Copy.spoken(["\(capCount) of \(capLimit) in \(Copy.next)"] + (visibleCountText.map { [$0] } ?? []))
    }

    /// Why the list shows fewer rows than the cap count says: `8 of 14 on the go` on the iPhone
    /// (whose hard context restriction hides the rest, E2), `3 of 14 shown` under a filter.
    /// `nil` when every Next action is on screen — nothing to explain.
    public var visibleCountText: String? {
        let visible = items.count
        guard visible != capCount || mode == .onTheGo else { return nil }
        switch mode {
        case .onTheGo: return "\(visible) of \(capCount) on the go"
        case .full: return "\(visible) of \(capCount) shown"
        }
    }

    // MARK: - Row content

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    public func projectTitle(for action: Action) -> String? {
        action.project.flatMap { model.snapshot.project($0)?.title }
    }

    /// `Project name · mac · phone · ≤30 min` — project first, contexts as plain lowercase text
    /// (STYLEGUIDE §3.3), as separate parts so the row can join them for display or speech.
    public func metaParts(for action: Action) -> [String] {
        var parts: [String] = []
        if let title = projectTitle(for: action) { parts.append(title) }
        parts.append(contentsOf: action.contexts)
        if let bucket = action.timeBucket { parts.append("\(Copy.timeBucket(bucket)) min") }
        return parts
    }

    /// What VoiceOver reads for a row's opening target: title, meta and badges as one element,
    /// the `·` separators spoken as pauses (STYLEGUIDE §8).
    public func spokenLabel(for action: Action) -> String {
        Copy.spoken([action.title] + metaParts(for: action) + badges(for: action).map(\.accessibilityLabel))
    }

    /// A2 — show the inline checklist once there is more than one checkbox to tick off.
    public func showsChecklist(_ action: Action) -> Bool { action.checkboxes.count >= 2 }

    /// True once every checkbox is ticked — the row then offers to complete the action,
    /// never completes it automatically (§1 "no lying UI").
    public func allChecked(_ action: Action) -> Bool {
        let boxes = action.checkboxes
        return !boxes.isEmpty && boxes.allSatisfy(\.done)
    }

    // MARK: - Row actions (mutating commands)

    /// Tick-off: completes immediately (N6 undo covers it). Used for both the row's leading
    /// control and the trailing full swipe.
    public func complete(_ action: Action) async throws {
        try await model.send(.complete(action.id))
    }

    public func toggleCheckbox(_ action: Action, index: Int) async throws {
        try await model.send(.toggleCheckbox(action.id, index: index))
    }

    /// Context menu / key: start working on it now. Only ever called on a row already in the
    /// Next list, so it can never increase cap occupancy (`next`/`in-progress` both count).
    public func start(_ action: Action) async throws {
        try await model.send(.setStatus(action.id, .inProgress, waiting: nil))
    }

    /// Context menu / leading swipe: send back to Backlog.
    public func demoteToBacklog(_ action: Action) async throws {
        try await model.send(.setStatus(action.id, .backlog, waiting: nil))
    }

    public func setWaiting(_ action: Action, _ info: WaitingInfo) async throws {
        try await model.send(.setStatus(action.id, .waiting, waiting: info))
    }

    /// The reducer refuses a future `deferDate` on a `next`/`in-progress` action outright (D1 ×
    /// A3: a deferred action cannot sit in Next) and never demotes it for you. Deferring a row
    /// out of this list therefore explicitly demotes to Backlog first, as its own command, then
    /// sets the date — two real, visible state changes, never a silent one.
    public func setDefer(_ action: Action, to day: Day?) async throws {
        if day != nil, action.status.countsTowardCap {
            try await model.send(.setStatus(action.id, .backlog, waiting: nil))
        }
        guard var updated = model.snapshot.action(action.id) else { return }
        updated.deferDate = day
        try await model.send(.updateAction(updated))
    }

    /// Chase quick action: push the follow-up out instead of chasing today.
    public func bumpFollowUp(_ action: Action, by days: Int = 7) async throws {
        guard let followUp = action.followUpDate else { return }
        try await model.send(.setStatus(
            action.id, .waiting,
            waiting: WaitingInfo(who: action.waitingFor ?? "", followUp: followUp.adding(days: days))))
    }

    /// Chase quick action: whatever you were waiting for arrived — the action is done.
    public func resolveChase(_ action: Action) async throws {
        try await model.send(.complete(action.id))
    }
}
