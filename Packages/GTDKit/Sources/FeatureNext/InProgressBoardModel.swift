import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// One column of the In progress board (#87): a board status and its cards.
public struct BoardColumn: Identifiable, Sendable, Equatable {
    public let status: ActionStatus
    public let actions: [Action]

    public var id: String { status.rawValue }
    public var title: String { Copy.status(status) }

    /// Where a card dropped on this column goes (`MovePlan`).
    public var destination: MoveDestination {
        InProgressBoardModel.destination(for: status) ?? .inProgress
    }

    public init(status: ActionStatus, actions: [Action]) {
        self.status = status
        self.actions = actions
    }
}

/// One choice of the board's project filter.
public struct BoardProjectChoice: Identifiable, Sendable, Equatable, Hashable {
    public let id: NoteID
    public let title: String

    public init(id: NoteID, title: String) {
        self.id = id
        self.title = title
    }
}

/// The In progress board (#87): three columns — In progress | Agent | Review — filtered by
/// context (like Next and Someday) and by project. Plain and unit-testable, **no SwiftUI**.
///
/// The filters live with the screen (not persisted): an empty filter shows everything, and
/// nothing is pre-selected (no lying defaults).
@MainActor
@Observable
public final class InProgressBoardModel {
    /// Context filter chips; empty = no context filter.
    public private(set) var contexts: [String] = []
    /// The project filter; `nil` = every project (and the cards without one).
    public private(set) var project: NoteID?

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var today: Day { model.today() }

    // MARK: - Filters

    public var availableContexts: [String] { model.snapshot.config.contexts }

    /// Every project a card on the board names, plus the chosen one if no card names it any
    /// more — a filter the person cannot see is a lying filter.
    public var availableProjects: [BoardProjectChoice] {
        var ids = Rules.boardProjects(model.snapshot, today: today)
        if let project, !ids.contains(project) { ids.append(project) }
        return ids.map { BoardProjectChoice(id: $0, title: title(of: $0)) }
    }

    public var isFiltered: Bool { !contexts.isEmpty || project != nil }

    public func setContexts(_ contexts: [String]) { self.contexts = contexts }

    public func toggleContext(_ context: String) {
        if let index = contexts.firstIndex(of: context) {
            contexts.remove(at: index)
        } else {
            contexts.append(context)
        }
    }

    public func setProject(_ project: NoteID?) { self.project = project }

    public func clearFilters() {
        contexts = []
        project = nil
    }

    /// The project filter's label: the chosen project's title, or `All projects`.
    public var projectFilterTitle: String {
        project.map(title(of:)) ?? Copy.allProjects
    }

    // MARK: - Columns

    /// The three columns, always all three, in `ActionStatus.boardStatuses` order.
    public var columns: [BoardColumn] {
        ActionStatus.boardStatuses.map { status in
            BoardColumn(
                status: status,
                actions: Rules.boardColumn(
                    model.snapshot, status: status, contexts: contexts, project: project,
                    today: today))
        }
    }

    /// True when no column has a card — the only time the empty state replaces the board.
    public var isEmpty: Bool { columns.allSatisfy(\.actions.isEmpty) }

    public var emptyStateTitle: String {
        isFiltered ? Copy.emptyNextFilteredTitle : Copy.emptyBoardTitle
    }

    public var emptyStateBody: String {
        isFiltered ? Copy.emptyBoardFilteredBody : Copy.emptyBoardBody
    }

    // MARK: - Cards

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    public func projectTitle(for action: Action) -> String? {
        action.project.map(title(of:))
    }

    /// The other columns a card can be moved to from its menu.
    public func moveTargets(for action: Action) -> [ActionStatus] {
        ActionStatus.boardStatuses.filter { $0 != action.status }
    }

    /// The `MoveDestination` of a board status; `nil` for a status that has no column.
    nonisolated public static func destination(for status: ActionStatus) -> MoveDestination? {
        switch status {
        case .inProgress: .inProgress
        case .agent: .agent
        case .review: .review
        default: nil
        }
    }

    private func title(of id: NoteID) -> String {
        model.snapshot.project(id)?.title ?? id.title
    }
}
