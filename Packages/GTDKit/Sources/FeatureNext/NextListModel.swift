import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Which Next list this is (N5): the Mac's full list, or the iPhone's on-the-go list.
public enum NextViewMode: String, Sendable, Equatable, Hashable, CaseIterable, CustomStringConvertible {
    case full
    /// iPhone: filtered to `config.onTheGoContexts` by default (E2). The context chips cannot
    /// lift that restriction; only switching the explicit `Only mobile` chip off (`showsAllContexts`) can.
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
    /// iPhone only (E2): `true` once the user switched the on-the-go restriction off to see every
    /// open Next action. Off by default; remembered per device. Ignored in `.full`, which never
    /// restricts. Mutate through `setShowsAllContexts`.
    public private(set) var showsAllContexts: Bool

    private let model: AppModel
    private let store: any NextFilterStore

    public init(model: AppModel, mode: NextViewMode, store: any NextFilterStore = UserDefaultsNextFilterStore()) {
        self.model = model
        self.mode = mode
        self.store = store
        self.contexts = store.contexts(for: mode)
        self.timeAvailable = store.timeAvailable(for: mode)
        self.showsAllContexts = store.showsAllContexts(for: mode)
    }

    public var today: Day { model.today() }

    // MARK: - Filters (E1)

    /// True while the list is restricted to the on-the-go contexts: the iPhone, unless the user
    /// switched `Only mobile` off (E2).
    public var isOnTheGoOnly: Bool { mode == .onTheGo && !showsAllContexts }

    /// Contexts the chips may offer — the on-the-go restriction narrows the set, and the chips
    /// themselves cannot lift it (E2); only `setShowsAllContexts(true)` does.
    public var availableContexts: [String] {
        isOnTheGoOnly ? model.snapshot.config.onTheGoContexts : model.snapshot.config.contexts
    }

    /// E2 — lifts (`true`) or restores (`false`) the on-the-go restriction. Restoring it drops
    /// picked contexts that are not on the go: their chips disappear, and a selection the user
    /// can no longer see or clear would be a lying filter.
    public func setShowsAllContexts(_ showsAll: Bool) {
        showsAllContexts = showsAll
        if isOnTheGoOnly {
            let allowed = Set(model.snapshot.config.onTheGoContexts)
            contexts.removeAll { !allowed.contains($0) }
        }
        persist()
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
        store.save(showsAllContexts: showsAllContexts, for: mode)
    }

    // MARK: - Lists

    /// Chase items (W2) — their own section above Next, unaffected by the context/time filters:
    /// chasing someone is never about what fits your current context.
    public var chase: [Action] { Rules.chaseItems(model.snapshot, today: today) }

    /// The Next list itself: in-progress pinned on top, then Next.
    public var items: [Action] {
        if isOnTheGoOnly {
            Rules.onTheGoNextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        } else {
            Rules.nextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        }
    }

    /// True once both sections are empty — the only time the big empty state replaces the list.
    public var isEmpty: Bool { items.isEmpty && chase.isEmpty }

    public var emptyStateTitle: String { isFiltered ? Copy.emptyNextFilteredTitle : Copy.emptyNextTitle }
    public var emptyStateBody: String { isFiltered ? Copy.emptyNextFilteredBody : Copy.emptyNextBody }

    // MARK: - Cap (STYLEGUIDE §2.2)

    /// How many actions occupy a Next slot right now — independent of the view's own filters.
    public var capCount: Int { Rules.countsTowardCap(model.snapshot, today: today) }

    /// `nil` below the cap (render `capCount` as a plain number); `15/15` at the cap; overdue
    /// styling above it. Never a meter/progress component.
    public var capBadge: BadgeContent? {
        Rules.capSignal(model.snapshot, today: today).map { SignalPresentation.badge(for: $0, today: today) }
    }

    /// The cap the count is measured against (`config.nextCap`).
    public var capLimit: Int { model.snapshot.config.nextCap }

    /// A3 — Next holds more than the cap allows. Only reachable without the user's consent
    /// through R-2: a deferred Next item comes back on its date into an already full list.
    public var isOverCap: Bool { capCount > capLimit }

    /// R-2 — nothing is demoted automatically when a deferred item returns into a full Next.
    /// The over-cap signal (`16/15`) shows, and the view presents the `Next is full` sheet
    /// **once per foreground** until the user has demoted something.
    ///
    /// The flag is the whole decision; presenting the sheet is the view's job (T11). It starts
    /// armed, because opening the app *is* the first foreground of a session.
    private var capSheetArmed = true

    /// True while the view still owes the user the `Next is full` sheet this foreground.
    public var showsCapSheet: Bool { capSheetArmed && isOverCap }

    /// The app came to the foreground: the sheet is due again if Next is still over the cap.
    public func enteredForeground() { capSheetArmed = true }

    /// The view has shown the sheet. It stays down until the next foreground, whatever the user
    /// chose — demoting clears `isOverCap` too, so a repaired list never re-arms it.
    public func capSheetShown() { capSheetArmed = false }

    /// The Next section's header label — `Next · 14/15`. Never a bare number: a count without
    /// its label and its limit says nothing (walkthrough P13). At/above the cap the view shows
    /// `Copy.next` plus `capBadge` instead, which carries the same `15/15`.
    public var capHeaderText: String { "\(Copy.next) · \(capCount)/\(capLimit)" }

    /// VoiceOver wording for the header — the `·` and `/` are not spoken as symbols.
    public var capHeaderSpokenText: String {
        Copy.spoken(["\(capCount) of \(capLimit) in \(Copy.next)"] + (visibleCountText.map { [$0] } ?? []))
    }

    /// Why the list shows fewer rows than the cap count says: `8 of 14 on the go` on the iPhone
    /// (whose context restriction hides the rest, E2), `3 of 14 shown` under a filter — also on
    /// the iPhone once `Only mobile` is off.
    /// `nil` when every Next action is on screen — nothing to explain.
    public var visibleCountText: String? {
        let visible = items.count
        guard visible != capCount || isOnTheGoOnly else { return nil }
        return isOnTheGoOnly ? "\(visible) of \(capCount) on the go" : "\(visible) of \(capCount) shown"
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

    /// One row of the inline checklist: a checkbox (with its `toggleCheckbox` index and nesting
    /// depth), or the `…` that stands for the steps the preview leaves out.
    public enum ChecklistRow: Hashable, Sendable {
        case step(index: Int, checkbox: Checkbox, depth: Int)
        case more
    }

    /// The inline checklist is a preview, never more than three rows: up to three steps are
    /// shown as they are; more become the first two and `…` (the rest live in the detail).
    public func checklistPreview(_ action: Action) -> [ChecklistRow] {
        let steps = Checkbox.scanNested(action.what).enumerated().map { index, entry in
            ChecklistRow.step(index: index, checkbox: entry.checkbox, depth: entry.depth)
        }
        guard steps.count > Self.checklistPreviewLimit else { return steps }
        return Array(steps.prefix(Self.checklistPreviewLimit - 1)) + [.more]
    }

    static let checklistPreviewLimit = 3

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

    /// Context menu / leading swipe: send back to Someday.
    public func demoteToSomeday(_ action: Action) async throws {
        try await model.send(.setStatus(action.id, .someday, waiting: nil))
    }

    public func setWaiting(_ action: Action, _ info: WaitingInfo) async throws {
        try await model.send(.setStatus(action.id, .waiting, waiting: info))
    }

    /// R-2/#86 — deferring is waiting: the row moves to Waiting with `day` as its follow-up
    /// date and no who, stops occupying a slot (`Rules.countsTowardCap(_:today:)`), and on
    /// that day comes back into Next by itself with the `back` badge. A chase item keeps the
    /// who it waits on and only gets the new date. A cleared date changes nothing.
    public func setDefer(_ action: Action, to day: Day?) async throws {
        guard let day, let current = model.snapshot.action(action.id) else { return }
        let who = current.status == .waiting ? current.waitingFor : nil
        try await model.send(.setStatus(current.id, .waiting, waiting: WaitingInfo(who: who, followUp: day)))
    }

    /// Chase quick action: push the follow-up out instead of chasing today.
    public func bumpFollowUp(_ action: Action, by days: Int = 7) async throws {
        guard let followUp = action.followUpDate else { return }
        try await model.send(.setStatus(
            action.id, .waiting,
            waiting: WaitingInfo(who: action.waitingFor, followUp: followUp.adding(days: days))))
    }

    /// Chase quick action: whatever you were waiting for arrived — the action is done.
    public func resolveChase(_ action: Action) async throws {
        try await model.send(.complete(action.id))
    }

    // MARK: - Chase row title (STYLEGUIDE §3.3, W1/D39's optional who)

    /// `Chase: <who> — <what>` when a who is on file, `Chase: <what>` when it is empty/nil —
    /// never a dangling "— " suffix. Pure, so it is testable without SwiftUI (ARCHITECTURE §5).
    public func chaseTitle(for action: Action) -> String {
        NextListModel.chaseTitle(who: action.waitingFor, what: action.title)
    }

    static func chaseTitle(who: String?, what: String) -> String {
        guard let who, !who.isEmpty else { return "\(Copy.chase): \(what)" }
        return "\(Copy.chase): \(who) — \(what)"
    }

    /// VoiceOver label for a chase row: the built title, then meta and badges as usual.
    public func chaseSpokenLabel(for action: Action) -> String {
        Copy.spoken([chaseTitle(for: action)] + metaParts(for: action) + badges(for: action).map(\.accessibilityLabel))
    }
}
