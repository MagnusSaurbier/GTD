import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureOverview

/// Grouping (E3: by area / project) and filtering (context, time, ⌘F title filter).
@MainActor
struct ActionListModelTests {

    private func makeModel(_ snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test",
                                     env: { Fixtures.reducerEnv(deviceID: "test") }),
            snapshot: snapshot,
            today: { Fixtures.today })
    }

    private func action(
        _ title: String,
        status: ActionStatus = .backlog,
        project: NoteID? = nil,
        contexts: [String] = [],
        minutes: Int? = nil,
        due: Day? = nil,
        deferDate: Day? = nil
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/\(title).md"),
            title: title,
            status: status,
            contexts: contexts,
            timeEstimate: minutes,
            project: project,
            deferDate: deferDate,
            due: due)
    }

    // MARK: - Grouping

    /// ARCHITECTURE §6: actions without a project come first and get **no** section header.
    @Test func ungroupedActionsComeFirstWithoutAHeader() {
        let snapshot = Fixtures.sampleSnapshot
        let groups = ActionListModel.group(
            [
                action("Zebra", project: Fixtures.daadProject.id),
                action("Alone"),
            ],
            in: snapshot)

        #expect(groups.count == 2)
        #expect(groups[0].title == nil)
        #expect(groups[0].project == nil)
        #expect(groups[0].actions.map(\.title) == ["Alone"])
        #expect(groups[1].title == Fixtures.daadProject.title)
    }

    @Test func noUngroupedSectionWhenEveryActionHasAProject() {
        let groups = ActionListModel.group(
            [action("A", project: Fixtures.daadProject.id)], in: Fixtures.sampleSnapshot)
        #expect(groups.count == 1)
        #expect(groups[0].title != nil)
    }

    /// Sections sort by area title, then project title — the "by area / project" of E3.
    @Test func sectionsSortByAreaThenProject() {
        let snapshot = Fixtures.sampleSnapshot
        let groups = ActionListModel.group(
            [
                action("c", project: Fixtures.thesisProject.id),      // Karriereplanung
                action("a", project: Fixtures.daadProject.id),        // Applications
                action("b", project: Fixtures.erasmusProject.id),     // Applications
            ],
            in: snapshot)

        let areas = groups.map { ActionListModel.areaTitle(of: $0.project!, in: snapshot) }
        #expect(areas == areas.sorted())
        #expect(groups.first?.title == Fixtures.daadProject.title)
        #expect(groups.last?.title == Fixtures.thesisProject.title)
    }

    @Test func actionsInsideASectionSortByDueThenTitle() {
        let project = Fixtures.daadProject.id
        let groups = ActionListModel.group(
            [
                action("no due b", project: project),
                action("later", project: project, due: Fixtures.day(5)),
                action("no due a", project: project),
                action("soon", project: project, due: Fixtures.day(1)),
            ],
            in: Fixtures.sampleSnapshot)

        #expect(groups[0].actions.map(\.title) == ["soon", "later", "no due a", "no due b"])
    }

    @Test func aDanglingProjectLinkStillGetsAHeader() {
        let ghost = NoteID(path: "Projects/Gone/Gone.md")
        let groups = ActionListModel.group([action("x", project: ghost)], in: Fixtures.sampleSnapshot)
        #expect(groups[0].title == "Gone")
    }

    // MARK: - Filtering

    @Test func titleFilterIsCaseInsensitiveSubstring() {
        let actions = [action("Fix the bike light"), action("Return the library books")]
        #expect(ActionListModel.filter(actions, query: "BIKE", contexts: [], timeAvailable: nil)
            .map(\.title) == ["Fix the bike light"])
        #expect(ActionListModel.filter(actions, query: "  ", contexts: [], timeAvailable: nil).count == 2)
        #expect(ActionListModel.filter(actions, query: "zzz", contexts: [], timeAvailable: nil).isEmpty)
    }

    @Test func contextFilterMatchesAnySelectedContext() {
        let actions = [
            action("a", contexts: ["mac", "deep-work"]),
            action("b", contexts: ["errands"]),
            action("c"),
        ]
        #expect(ActionListModel.filter(actions, query: "", contexts: ["mac"], timeAvailable: nil)
            .map(\.title) == ["a"])
        #expect(ActionListModel.filter(actions, query: "", contexts: ["mac", "errands"], timeAvailable: nil)
            .map(\.title) == ["a", "b"])
    }

    /// "No lying defaults": an undecided estimate is never filtered away.
    @Test func timeFilterKeepsUndecidedEstimates() {
        let actions = [action("quick", minutes: 10), action("long", minutes: 90), action("unknown")]
        #expect(ActionListModel.filter(actions, query: "", contexts: [], timeAvailable: 30)
            .map(\.title) == ["quick", "unknown"])
    }

    // MARK: - Against the live snapshot

    @Test func listShowsOnlyItsStatusAndHidesDeferredItems() {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.actions.append(action("Deferred backlog item", deferDate: Fixtures.day(4)))
        snapshot.actions.append(action("Plain backlog item"))
        let list = ActionListModel(model: makeModel(snapshot), status: .backlog)

        let titles = list.actions.map(\.title)
        #expect(titles.contains("Plain backlog item"))
        #expect(!titles.contains("Deferred backlog item"))
        #expect(list.actions.allSatisfy { $0.status == .backlog })
        #expect(list.isFiltered == false)
    }

    @Test func clearFiltersResetsEverything() {
        let list = ActionListModel(model: makeModel(), status: .maybe)
        list.query = "bike"
        list.contexts = ["mac"]
        list.timeAvailable = 30
        #expect(list.isFiltered)
        list.clearFilters()
        #expect(list.isFiltered == false)
        #expect(list.query.isEmpty && list.contexts.isEmpty && list.timeAvailable == nil)
    }

    @Test func groupsAndActionsAgree() {
        let list = ActionListModel(model: makeModel(), status: .backlog)
        #expect(list.groups.reduce(0) { $0 + $1.actions.count } == list.actions.count)
    }
}
