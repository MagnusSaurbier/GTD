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

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var today: Day { model.today() }

    /// Rows grouped by area, areas in vault order; projects without an area come first
    /// without a section header (ARCHITECTURE §6).
    public var sections: [(area: Area?, rows: [Rules.ProjectRow])] {
        let all = Rules.projectRows(model.snapshot, today: today)
            .filter { statuses.isEmpty || statuses.contains($0.project.status) }
        var out: [(Area?, [Rules.ProjectRow])] = []
        let ungrouped = all.filter { $0.project.area == nil }
        if !ungrouped.isEmpty { out.append((nil, ungrouped)) }
        for area in model.snapshot.areas {
            let rows = all.filter { $0.project.area == area.id }
            if !rows.isEmpty { out.append((area, rows)) }
        }
        return out.map { (area: $0.0, rows: $0.1) }
    }

    /// Steps that `WhatsNextSheet` offers for one-tap promotion (P5).
    public func openSteps(of project: NoteID) -> [ProjectStep] {
        model.snapshot.project(project)?.openSteps ?? []
    }

    /// How many Next actions a status change would demote (P3) — shown before confirming.
    public func demotionCount(for project: NoteID) -> Int {
        model.snapshot.actions.count { $0.project == project && $0.status.countsTowardCap }
    }
}
