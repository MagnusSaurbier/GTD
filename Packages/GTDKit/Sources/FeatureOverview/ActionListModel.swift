import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// One section of a grouped action list (E3): actions of one project, or the leading group of
/// actions that belong to no project — which is listed **first and without a header**
/// (ARCHITECTURE §6: no "No project" vocabulary).
public struct ActionGroup: Identifiable, Sendable, Equatable {
    /// `""` for the ungrouped leading section, otherwise the project's path.
    public let id: String
    /// `nil` ⇒ render no section header.
    public let title: String?
    public let project: NoteID?
    public let actions: [Action]

    public init(id: String, title: String?, project: NoteID?, actions: [Action]) {
        self.id = id
        self.title = title
        self.project = project
        self.actions = actions
    }
}

/// The generic list of one action status (Backlog / Maybe) — grouping, filtering and badges.
/// No SwiftUI, so the rules are unit-tested on Linux (ARCHITECTURE §5).
///
/// Grouping is **by area / project** (E3). Context and time are *filters*, never groupings.
@MainActor
@Observable
public final class ActionListModel {
    public let status: ActionStatus
    /// Filter-as-you-type over titles (`⌘F`). Empty = no filter.
    public var query: String = ""
    /// Context filter chips; empty = no context filter (never a default selection).
    public var contexts: [String] = []
    /// Time available in minutes; `nil` = no time filter.
    public var timeAvailable: Int?

    private let model: AppModel

    public init(model: AppModel, status: ActionStatus) {
        self.model = model
        self.status = status
    }

    public var today: Day { model.today() }

    public var availableContexts: [String] { model.snapshot.config.contexts }

    public var isFiltered: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || !contexts.isEmpty || timeAvailable != nil
    }

    /// Everything the list shows, ungrouped — deferred items stay hidden until their day (D1).
    public var actions: [Action] {
        ActionListModel.filter(
            Rules.visibleActions(model.snapshot, today: today).filter { $0.status == status },
            query: query,
            contexts: contexts,
            timeAvailable: timeAvailable)
    }

    /// The list as the middle column renders it: ungrouped actions first, then one section per
    /// project, ordered by area title then project title.
    public var groups: [ActionGroup] {
        ActionListModel.group(actions, in: model.snapshot)
    }

    public var isEmpty: Bool { actions.isEmpty }

    public func clearFilters() {
        query = ""
        contexts = []
        timeAvailable = nil
    }

    public func badges(for action: Action) -> [BadgeContent] {
        SignalPresentation.badges(for: Rules.signals(for: action, today: today), today: today)
    }

    public func projectTitle(for action: Action) -> String? {
        action.project.flatMap { ActionListModel.title(of: $0, in: model.snapshot) }
    }

    // MARK: - Pure helpers (the part worth testing)

    /// Title filter (case-insensitive substring, no diacritic folding so it behaves identically
    /// on every platform), plus the context and time chips of E1/E3.
    public static func filter(
        _ actions: [Action],
        query: String,
        contexts: [String],
        timeAvailable: Int?
    ) -> [Action] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let wanted = Set(contexts)
        return actions.filter { action in
            if !needle.isEmpty, !action.title.lowercased().contains(needle) { return false }
            if !wanted.isEmpty, Set(action.contexts).isDisjoint(with: wanted) { return false }
            if let timeAvailable {
                // Undecided estimates are never filtered away (§1 "no lying defaults").
                if let bucket = action.timeBucket, !bucket.fits(available: timeAvailable) {
                    return false
                }
            }
            return true
        }
    }

    /// Groups by project (E3). Actions without a project come first, without a section header.
    /// Sections are ordered by area title, then project title; actions inside a section by due
    /// date, then title.
    public static func group(_ actions: [Action], in snapshot: VaultSnapshot) -> [ActionGroup] {
        var ungrouped: [Action] = []
        var byProject: [NoteID: [Action]] = [:]
        for action in actions {
            if let project = action.project {
                byProject[project, default: []].append(action)
            } else {
                ungrouped.append(action)
            }
        }

        var out: [ActionGroup] = []
        if !ungrouped.isEmpty {
            out.append(ActionGroup(
                id: "", title: nil, project: nil, actions: ungrouped.sorted(by: sorted)))
        }

        let sections = byProject.keys.map { id -> (area: String, title: String, id: NoteID) in
            (areaTitle(of: id, in: snapshot), title(of: id, in: snapshot), id)
        }
        for section in sections.sorted(by: { ($0.area, $0.title, $0.id.path) < ($1.area, $1.title, $1.id.path) }) {
            out.append(ActionGroup(
                id: section.id.path,
                title: section.title,
                project: section.id,
                actions: (byProject[section.id] ?? []).sorted(by: sorted)))
        }
        return out
    }

    /// A project's (or area's) display name; falls back to the file name for a dangling link.
    static func title(of id: NoteID, in snapshot: VaultSnapshot) -> String {
        snapshot.project(id)?.title ?? snapshot.area(id)?.title ?? id.title
    }

    /// The area a section sorts under; `""` sorts arealess projects first.
    static func areaTitle(of id: NoteID, in snapshot: VaultSnapshot) -> String {
        guard let project = snapshot.project(id) else { return "" }
        guard let area = project.area else { return "" }
        return snapshot.area(area)?.title ?? area.title
    }

    private static func sorted(_ lhs: Action, _ rhs: Action) -> Bool {
        let far = Day(year: 9999, month: 12, day: 31)
        return ((lhs.due ?? far), lhs.title) < ((rhs.due ?? far), rhs.title)
    }
}
