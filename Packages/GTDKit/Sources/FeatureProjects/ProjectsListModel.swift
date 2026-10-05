import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// Rows and grouping for the projects list (E4), plus the data the promotion flows need.
/// Plain and unit-testable — **no SwiftUI**. Owned by T22.
@MainActor
@Observable
public final class ProjectsListModel {
    /// Which statuses the list shows; empty = all.
    public var statuses: Set<ProjectStatus> = [.active]
    /// The Mac shell's ⌘F text (#98): narrows the rows by project title after the status chips,
    /// case-insensitively. `""` = no filter.
    public var query: String = ""

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var today: Day { model.today() }

    /// The filtered rows as a folder tree (#67): area-less projects (`Projects/no_area/…` and
    /// `Projects/<Name>/`) flat on top, every other project under the folders it sits in,
    /// alphabetical at every level. Folders without a visible project do not appear.
    public var tree: ProjectTree<Rules.ProjectRow> {
        let rows = Rules.projectRows(model.snapshot, today: today)
            .filter { statuses.isEmpty || statuses.contains($0.project.status) }
            .filter { Self.matches($0.project.title, query: query) }
        return ProjectTree(
            rows: rows, layout: model.snapshot.config.layout,
            id: \.project.id, title: \.project.title)
    }

    /// The rows `ProjectsListView` draws, given the folders collapsed on this device. While a
    /// query is typed every folder is open, so a match inside a folded folder still shows.
    public func lines(collapsed: Set<String>) -> [ProjectTree<Rules.ProjectRow>.Line] {
        tree.lines(collapsed: isFiltered ? [] : collapsed, id: \.project.id)
    }

    /// Whether a ⌘F query narrows the list — an empty list then says "No match", not "no projects".
    public var isFiltered: Bool { !Self.needle(query).isEmpty }

    /// Same rule as `ActionListModel.filter`: trimmed, case-insensitive substring of the title.
    static func matches(_ title: String, query: String) -> Bool {
        let needle = needle(query)
        return needle.isEmpty || title.lowercased().contains(needle)
    }

    private static func needle(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Steps that `WhatsNextSheet` offers for one-tap promotion (P5).
    public func openSteps(of project: NoteID) -> [ProjectStep] {
        model.snapshot.project(project)?.openSteps ?? []
    }

    /// How many Next actions a status change would demote (P3) — shown before confirming.
    public func demotionCount(for project: NoteID) -> Int {
        model.snapshot.actions.count { $0.project == project && $0.status.countsTowardCap }
    }

    /// Toggles one status in the list's filter set (E4 "Sections/filters"). Empty means "all" —
    /// `tree` treats it that way, so clearing the last filter shows every status again.
    public func toggleStatus(_ status: ProjectStatus) {
        if statuses.contains(status) {
            statuses.remove(status)
        } else {
            statuses.insert(status)
        }
    }

    // MARK: - Create area / project

    public func createArea(title: String) async throws {
        try await model.send(.createArea(title: title))
    }

    public func createProject(_ draft: ProjectDraft) async throws {
        try await model.send(.createProject(draft))
    }
}
