import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Which Next list this is (N5): the Mac's full list, or the iPhone's on-the-go list.
public enum NextViewMode: Sendable, Equatable, Hashable, CaseIterable {
    case full
    /// iPhone: hard-filtered to `config.onTheGoContexts`; the filter cannot be removed (E2).
    case onTheGo
}

/// Filtering, sections and ordering for the Next view (E1). Plain and unit-testable — **no
/// SwiftUI**. Owned by T21.
@MainActor
@Observable
public final class NextListModel {
    public let mode: NextViewMode
    /// Context filter chips; empty = no context filter (never a default selection).
    public var contexts: [String] = []
    /// Time available in minutes; `nil` = no time filter.
    public var timeAvailable: Int?

    private let model: AppModel

    public init(model: AppModel, mode: NextViewMode) {
        self.model = model
        self.mode = mode
    }

    public var today: Day { model.today() }

    /// Contexts the chips may offer (on-the-go mode narrows the set).
    public var availableContexts: [String] {
        mode == .onTheGo ? model.snapshot.config.onTheGoContexts : model.snapshot.config.contexts
    }

    /// Chase items (W2) — their own section above Next.
    public var chase: [Action] { Rules.chaseItems(model.snapshot, today: today) }

    /// The Next list itself: in-progress pinned on top.
    public var items: [Action] {
        switch mode {
        case .full:
            Rules.nextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        case .onTheGo:
            Rules.onTheGoNextList(model.snapshot, contexts: contexts, timeAvailable: timeAvailable, today: today)
        }
    }

    public var isFiltered: Bool { !contexts.isEmpty || timeAvailable != nil }

    /// `15/15` once the cap is reached (STYLEGUIDE §2.2). `nil` below the cap: a plain count.
    public var capBadge: BadgeContent? {
        Rules.capSignal(model.snapshot).map { SignalPresentation.badge(for: $0, today: today) }
    }

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    public func projectTitle(for action: Action) -> String? {
        action.project.flatMap { model.snapshot.project($0)?.title }
    }

    public func clearFilters() {
        contexts = []
        timeAvailable = nil
    }
}
