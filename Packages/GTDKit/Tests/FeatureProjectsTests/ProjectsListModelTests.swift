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

    @Test func ungroupedProjectsComeFirstWithoutAnAreaHeader() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []   // empty == "all" statuses
        let sections = list.sections
        #expect(sections.first?.area == nil)
        #expect(sections.first?.rows.contains { $0.project.id == Fixtures.flatProject.id } == true)
    }

    @Test func groupedSectionsFollowVaultAreaOrder() {
        let list = ProjectsListModel(model: makeModel())
        list.statuses = []
        let areaTitles = list.sections.compactMap(\.area?.title)
        #expect(areaTitles == Fixtures.areas.map(\.title))
    }

    @Test func defaultFilterShowsOnlyActiveProjects() {
        let list = ProjectsListModel(model: makeModel())
        #expect(list.statuses == [.active])
        let shown = Set(list.sections.flatMap(\.rows).map(\.project.id))
        #expect(shown.contains(Fixtures.daadProject.id))
        #expect(!shown.contains(Fixtures.sideJobProject.id))   // on-hold, filtered out by default
    }

    @Test func toggleStatusAddsAndRemovesAFilter() {
        let list = ProjectsListModel(model: makeModel())
        list.toggleStatus(.onHold)
        #expect(list.statuses == [.active, .onHold])
        let shown = Set(list.sections.flatMap(\.rows).map(\.project.id))
        #expect(shown.contains(Fixtures.sideJobProject.id))

        list.toggleStatus(.active)
        list.toggleStatus(.onHold)
        #expect(list.statuses.isEmpty)   // empty == every status shown again
        let all = Set(list.sections.flatMap(\.rows).map(\.project.id))
        #expect(all.count == Fixtures.projects.count)
    }

    @Test func stalledProjectIsFlaggedInItsRow() {
        let list = ProjectsListModel(model: makeModel())
        let flat = list.sections.flatMap(\.rows).first { $0.project.id == Fixtures.flatProject.id }
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
}
