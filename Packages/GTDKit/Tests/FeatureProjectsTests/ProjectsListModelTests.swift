import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureProjects

@MainActor
struct ProjectsListModelTests {

    private func makeModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test", env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    // MARK: - Grouping (E4)

    /// Every project row the list would show with nothing collapsed.
    private func visibleRows(_ list: ProjectsListModel) -> [Rules.ProjectRow] {
        list.lines(collapsed: []).compactMap {
            if case let .project(row, _, _) = $0 { row } else { nil }
        }
    }

    @Test func areaLessProjectsComeFirstWithoutAFolder() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []   // empty == "all" statuses
        #expect(list.tree.top.contains { $0.project.id == Fixtures.flatProject.id })
        guard case let .project(_, id, depth) = list.lines(collapsed: []).first else {
            Issue.record("first line is not a project"); return
        }
        #expect(id == Fixtures.flatProject.id)
        #expect(depth == 0)
    }

    @Test func areaFoldersAreTreeNodesAlphabetically() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []
        #expect(list.tree.nodes.map(\.name) == Fixtures.areas.map(\.id.folder).map { NoteID(path: $0).title }
            .sorted { $0.lowercased() < $1.lowercased() })
        let daad = list.tree.nodes.first { $0.projects.contains { $0.project.id == Fixtures.daadProject.id } }
        #expect(daad?.id == Fixtures.daadProject.id.folder.split(separator: "/").dropLast().joined(separator: "/"))
    }

    @Test func filteredOutFolderDisappears() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = [.onHold]
        let names = list.tree.nodes.map(\.name)
        let sideJobFolder = NoteID(path: Fixtures.sideJobProject.id.folder).folder
        #expect(names == [NoteID(path: sideJobFolder).title])
    }

    @Test func defaultFilterShowsOnlyActiveProjects() {
        let list = ProjectsListModel(model: makeModel())
        #expect(list.statuses == [.active])
        let shown = Set(visibleRows(list).map(\.project.id))
        #expect(shown.contains(Fixtures.daadProject.id))
        #expect(!shown.contains(Fixtures.sideJobProject.id))   // on-hold, filtered out by default
    }

    @Test func toggleStatusAddsAndRemovesAFilter() {
        let list = ProjectsListModel(model: makeModel())
        list.toggleStatus(.onHold)
        #expect(list.statuses == [.active, .onHold])
        let shown = Set(visibleRows(list).map(\.project.id))
        #expect(shown.contains(Fixtures.sideJobProject.id))

        list.toggleStatus(.active)
        list.toggleStatus(.onHold)
        #expect(list.statuses.isEmpty)   // empty == every status shown again
        let all = Set(visibleRows(list).map(\.project.id))
        #expect(all.count == Fixtures.projects.count)
    }

    @Test func stalledProjectIsFlaggedInItsRow() {
        let list = ProjectsListModel(model: makeModel())
        let flat = visibleRows(list).first { $0.project.id == Fixtures.flatProject.id }
        #expect(flat?.isStalled == true)
        #expect(flat?.activeActions.isEmpty == true)
    }

    // MARK: - What's-next support

    @Test func openStepsExcludesDoneAndPromotedSteps() {
        let list = ProjectsListModel(model: makeModel())
        let open = list.openSteps(of: Fixtures.daadProject.id)
        // "Collect transcripts" is done+promoted, "Write motivation letter" is already promoted
        // (the in-progress action of the same name) — both excluded.
        #expect(open.map(\.text) == ["Ask Prof. Weber for a reference", "Submit the online form"])
        #expect(!open.contains { $0.done })
        #expect(!open.contains { $0.promotedTo != nil })
    }

    @Test func demotionCountCountsOnlyActionsThatCountTowardTheCap() {
        let list = ProjectsListModel(model: makeModel())
        let count = list.demotionCount(for: Fixtures.daadProject.id)
        let expected = Fixtures.sampleSnapshot.actions
            .count { $0.project == Fixtures.daadProject.id && $0.status.countsTowardCap }
        #expect(count == expected)
        #expect(count > 0)
    }

    // MARK: - Create area / project

    @Test func createAreaAddsIt() async throws {
        let model = makeModel()
        let list = ProjectsListModel(model: model)
        try await list.createArea(title: "Health")
        #expect(model.snapshot.areas.contains { $0.title == "Health" })
    }

    @Test func createProjectAddsItAsActive() async throws {
        let model = makeModel()
        let list = ProjectsListModel(model: model)
        try await list.createProject(ProjectDraft(title: "New roof", outcome: "Roof replaced"))
        let created = model.snapshot.projects.first { $0.title == "New roof" }
        #expect(created?.status == .active)
        #expect(created?.outcome == "Roof replaced")
    }

    @Test func createProjectWithANewAreaCreatesBoth() async throws {
        let model = makeModel()
        let list = ProjectsListModel(model: model)
        try await list.createProject(ProjectDraft(title: "Ski trip", newAreaTitle: "Leisure"))
        let area = model.snapshot.areas.first { $0.title == "Leisure" }
        #expect(area != nil)
        #expect(model.snapshot.projects.first { $0.title == "Ski trip" }?.area == area?.id)
    }

    @Test func createProjectWithACollidingTitleThrows() async throws {
        let model = makeModel()
        let list = ProjectsListModel(model: model)
        // `flatProject` has no area, so an area-less draft with the same title collides.
        await #expect(throws: GTDError.self) {
            try await list.createProject(ProjectDraft(title: Fixtures.flatProject.title))
        }
    }

    // MARK: - ⌘F query (#98)

    @Test func queryNarrowsRowsByTitleCaseInsensitively() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []
        list.query = "  daA "
        #expect(list.isFiltered)
        #expect(visibleRows(list).map(\.project.id) == [Fixtures.daadProject.id])
    }

    @Test func queryShowsMatchesInsideCollapsedFolders() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []
        let folder = Fixtures.daadProject.id.folder.split(separator: "/").dropLast().joined(separator: "/")
        list.query = "DAAD"
        let ids = list.lines(collapsed: [folder]).compactMap {
            if case let .project(_, id, _) = $0 { id } else { nil }
        }
        #expect(ids == [Fixtures.daadProject.id])
    }

    @Test func queryKeepsTheStatusChips() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = [.done]
        list.query = Fixtures.flatProject.title
        #expect(Fixtures.flatProject.status == .active)
        #expect(list.tree.isEmpty)
    }

    @Test func clearingTheQueryRestoresTheList() {
        let list = ProjectsListModel(model: makeModel())
        let before = visibleRows(list).map(\.project.id)
        list.query = "zzz no such project"
        #expect(visibleRows(list).isEmpty)
        list.query = ""
        #expect(!list.isFiltered)
        #expect(visibleRows(list).map(\.project.id) == before)
    }
}
