import Testing
import Foundation
import GTDModel
import GTDFixtures

/// P1–P5 — areas, projects, the "only active projects reach Next" rule, promotion and
/// "Turn into project".
struct ReducerProjectTests {
    private let env = TestVault.env()

    // MARK: - P1: areas and projects

    @Test func creatingAnAreaAndAProjectInsideIt() throws {
        var vault = TestVault.snapshot()
        let withArea = try Reducer.reduce(vault, .createArea(title: "Wohnen"), env: env)
        let area = try #require(withArea.snapshot.areas.first)
        #expect(area.id.path == "Projects/Wohnen/Wohnen.md")

        vault = withArea.snapshot
        let withProject = try Reducer.reduce(
            vault, .createProject(ProjectDraft(title: "Umzug", area: area.id, outcome: "Vertrag unterschrieben")),
            env: env)
        let project = try #require(withProject.snapshot.projects.first)
        #expect(project.id.path == "Projects/Wohnen/Umzug/Umzug.md")
        #expect(project.status == .active)
        #expect(project.outcome == "Vertrag unterschrieben")
    }

    @Test func aProjectWithoutAnAreaLivesDirectlyUnderProjects() throws {
        let result = try Reducer.reduce(
            TestVault.snapshot(), .createProject(ProjectDraft(title: "Wohnungssuche")), env: env)
        #expect(result.snapshot.projects.first?.id.path == "Projects/Wohnungssuche/Wohnungssuche.md")
        #expect(result.snapshot.projects.first?.area == nil)
    }

    @Test func creatingTheAreaAlongsideTheProjectReusesAnExistingOne() throws {
        let existing = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        let vault = TestVault.snapshot(areas: [existing])
        let result = try Reducer.reduce(
            vault, .createProject(ProjectDraft(title: "Umzug", newAreaTitle: "Wohnen")), env: env)
        #expect(result.snapshot.areas.count == 1)
        #expect(result.snapshot.projects.first?.area == existing.id)
    }

    @Test func creatingAnAreaThatExistsIsACollision() {
        let existing = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        #expect(TestVault.error(TestVault.snapshot(areas: [existing]), .createArea(title: "Wohnen"), env: env)
                == .titleCollision("Wohnen"))
    }

    @Test func projectsAndAreasNeedATitle() {
        #expect(TestVault.error(TestVault.snapshot(), .createArea(title: " "), env: env)
                == .invalid("A title is required"))
        #expect(TestVault.error(TestVault.snapshot(), .createProject(ProjectDraft(title: "")), env: env)
                == .invalid("A title is required"))
    }

    @Test func aProjectInAnUnknownAreaIsNotFound() {
        let ghost = TestVault.layout.areaPath(title: "Ghost")
        #expect(TestVault.error(TestVault.snapshot(), .createProject(ProjectDraft(title: "P", area: ghost)), env: env)
                == .notFound(ghost))
    }

    @Test func emptyStepsAreDropped() throws {
        let result = try Reducer.reduce(
            TestVault.snapshot(),
            .createProject(ProjectDraft(title: "Umzug", steps: ["Kartons kaufen", "  ", ""])), env: env)
        #expect(result.snapshot.projects.first?.steps.map(\.text) == ["Kartons kaufen"])
    }

    // MARK: - P3: only active projects put actions into Next

    @Test(arguments: [ProjectStatus.onHold, .someday, .done])
    func anInactiveProjectCannotTakeANextAction(status: ProjectStatus) {
        let project = TestVault.project("Nebenjob", status: status)
        let vault = TestVault.snapshot(projects: [project])
        for actionStatus in [ActionStatus.next, .inProgress] {
            let error = TestVault.error(vault, .createAction(ActionDraft(
                title: "CV updaten", status: actionStatus, contexts: ["mac"], timeEstimate: 10,
                project: project.id, why: "Bewerbung", what: "CV updaten")), env: env)
            #expect(error == .invalid("Only active projects put actions into Next"))
        }
        // …but the Someday tier and waiting are fine.
        #expect(TestVault.error(vault, .createAction(ActionDraft(
            title: "CV updaten", status: .someday, project: project.id,
            what: "CV updaten")), env: env) == nil)
    }

    @Test(arguments: [ProjectStatus.onHold, .someday, .done])
    func leavingActiveDemotesTheProjectsNextActions(status: ProjectStatus) throws {
        let project = TestVault.project("DAAD")
        let vault = TestVault.snapshot(
            actions: [
                TestVault.action("Letter", .inProgress, project: project.id),
                TestVault.action("Form", .next, project: project.id),
                TestVault.action("Bib", .waiting, project: project.id,
                                 waiting: WaitingInfo(who: "Bib", followUp: TestVault.day(3))),
                TestVault.action("Fremd", .next),
            ],
            projects: [project])

        var changed = project
        changed.status = status
        let result = try Reducer.reduce(vault, .updateProject(changed), env: env)

        #expect(result.snapshot.action(TestVault.actionID("Letter"))?.status == .someday)
        #expect(result.snapshot.action(TestVault.actionID("Form"))?.status == .someday)
        #expect(result.snapshot.action(TestVault.actionID("Bib"))?.status == .waiting)    // untouched
        #expect(result.snapshot.action(TestVault.actionID("Fremd"))?.status == .next)     // other project
        #expect(Rules.countsTowardCap(result.snapshot, today: env.today) == 1)
    }

    /// A vault edited by hand can hold a Next action under an on-hold project; the next
    /// `updateProject` repairs it instead of preserving the contradiction.
    @Test func updatingAnAlreadyInactiveProjectStillDemotes() throws {
        let project = TestVault.project("Nebenjob", status: .onHold)
        let vault = TestVault.snapshot(
            actions: [TestVault.action("CV", .next, project: project.id)], projects: [project])
        var edited = project
        edited.outcome = "Working-student job"
        let result = try Reducer.reduce(vault, .updateProject(edited), env: env)
        #expect(result.snapshot.actions[0].status == .someday)
    }

    @Test func reactivatingAProjectDoesNotPromoteAnything() throws {
        let project = TestVault.project("DAAD", status: .onHold)
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Letter", .someday, project: project.id)], projects: [project])
        var active = project
        active.status = .active
        let result = try Reducer.reduce(vault, .updateProject(active), env: env)
        #expect(result.snapshot.actions[0].status == .someday)   // never automatic (I4)
    }

    @Test func renamingOrMovingAProjectIsRefused() {
        let area = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        let project = TestVault.project("DAAD")
        let vault = TestVault.snapshot(areas: [area], projects: [project])

        var renamed = project
        renamed.title = "DAAD 2027"
        #expect(TestVault.error(vault, .updateProject(renamed), env: env)
                == .invalid("Renaming a project is not supported"))

        var moved = project
        moved.area = area.id
        #expect(TestVault.error(vault, .updateProject(moved), env: env)
                == .invalid("Moving a project to another area is not supported"))
    }

    @Test func updatingAnUnknownProjectIsNotFound() {
        let ghost = TestVault.project("Ghost")
        #expect(TestVault.error(TestVault.snapshot(), .updateProject(ghost), env: env) == .notFound(ghost.id))
    }

    // MARK: - P4: promotion

    @Test func promotingAStepCreatesTheLinkedAction() throws {
        let project = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Write the motivation letter"),
        ])
        let vault = TestVault.snapshot(projects: [project])
        let result = try Reducer.reduce(
            vault, .promoteStep(project: project.id, stepIndex: 0, ActionDraft(
                title: "", status: .next, contexts: ["mac"], timeEstimate: 30,
                why: "The application needs it.")), env: env)

        let action = try #require(result.snapshot.actions.first)
        #expect(action.title == "Write the motivation letter")   // the step's own wording
        #expect(action.project == project.id)
        #expect(action.status == .next)
        #expect(result.snapshot.projects[0].steps[0].promotedTo == action.id)
        #expect(result.snapshot.projects[0].openSteps.isEmpty)
    }

    @Test func promotingRespectsTheCapAndTheProjectStatus() {
        let project = TestVault.project("DAAD", steps: [ProjectStep(text: "Write")])
        var full = TestVault.nextOccupied(15)
        full.projects = [project]
        #expect(TestVault.error(full, .promoteStep(
            project: project.id, stepIndex: 0,
            ActionDraft(title: "Write", status: .next, contexts: ["mac"], timeEstimate: 30,
                        why: "It is due.")), env: env)
                == .nextCapReached(cap: 15))

        let onHold = TestVault.project("Nebenjob", status: .onHold, steps: [ProjectStep(text: "CV")])
        #expect(TestVault.error(TestVault.snapshot(projects: [onHold]),
                                .promoteStep(project: onHold.id, stepIndex: 0, ActionDraft(
                                    title: "CV", status: .next, contexts: ["mac"],
                                    timeEstimate: 30, why: "Bewerbung")), env: env)
                == .invalid("Only active projects put actions into Next"))
    }

    @Test func aStepIsPromotedOnlyOnce() {
        let project = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Collect", done: true),
            ProjectStep(text: "Write", promotedTo: TestVault.actionID("Write")),
            ProjectStep(text: "Submit"),
        ])
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Write", .next, project: project.id)], projects: [project])
        let draft = ActionDraft(title: "Noch mal", status: .someday)

        #expect(TestVault.error(vault, .promoteStep(project: project.id, stepIndex: 0, draft), env: env)
                == .invalid("This step is already done"))
        #expect(TestVault.error(vault, .promoteStep(project: project.id, stepIndex: 1, draft), env: env)
                == .invalid("This step is already promoted"))
        #expect(TestVault.error(vault, .promoteStep(project: project.id, stepIndex: 9, draft), env: env)
                == .invalid("No step at index 9"))
        #expect(TestVault.error(vault, .promoteStep(project: project.id, stepIndex: 2, draft), env: env) == nil)
    }

    // MARK: - A2: turn into project

    @Test func convertingAnActionUsesItsCheckboxesAsSteps() throws {
        let action = TestVault.action(
            "Umzug organisieren", .next,
            why: "Der Untermietvertrag endet im März.",
            what: "- [ ] Kartons kaufen\n- [x] Nachsendeauftrag\n- [ ] Ummelden")
        let vault = TestVault.snapshot(actions: [action])
        #expect(Rules.suggestsProject(action))

        let result = try Reducer.reduce(
            vault, .convertActionToProject(action.id, ProjectDraft(title: "Umzug")), env: env)

        let project = try #require(result.snapshot.projects.first)
        #expect(project.steps.map(\.text) == ["Kartons kaufen", "Nachsendeauftrag", "Ummelden"])
        #expect(project.why == action.why)                       // carried over, not invented
        #expect(project.outcome.isEmpty)                         // undecided stays empty (§1)
        #expect(result.snapshot.action(action.id) == nil)
        #expect(result.extraOps == [.move(from: action.id.path, to: "GTD/Trash/Umzug organisieren.md")])
        // P4/P5 — the new project would be stalled, so the user is asked for the first step.
        #expect(result.prompts == [.whatsNext(project: project.id)])
    }

    @Test func convertingKeepsAnExplicitDraftOverTheActionsContent() throws {
        let action = TestVault.action("Umzug", .next, why: "alt", what: "- [ ] A\n- [ ] B")
        let result = try Reducer.reduce(
            TestVault.snapshot(actions: [action]),
            .convertActionToProject(action.id, ProjectDraft(
                title: "Umzug 2027", why: "neu", steps: ["Erst das"])), env: env)
        let project = try #require(result.snapshot.projects.first)
        #expect(project.why == "neu")
        #expect(project.steps.map(\.text) == ["Erst das"])
    }

    @Test func convertingClearsAStepThatPointedAtTheAction() throws {
        let old = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Write", promotedTo: TestVault.actionID("Write")),
        ])
        let action = TestVault.action("Write", .next, project: old.id, what: "- [ ] A\n- [ ] B")
        let result = try Reducer.reduce(
            TestVault.snapshot(actions: [action], projects: [old]),
            .convertActionToProject(action.id, ProjectDraft(title: "Letter")), env: env)
        let daad = try #require(result.snapshot.project(old.id))
        #expect(daad.steps[0].promotedTo == nil)     // no dangling link
    }

    // MARK: - P4 against the realistic vault

    @Test func theStalledProjectIsTheOneWithoutAVisibleOpenAction() {
        let vault = Fixtures.sampleSnapshot
        #expect(Rules.stalledProjects(vault, today: Fixtures.today).map(\.id) == [Fixtures.flatProject.id])
        // Its only action is deferred into the future, so nothing is moving today (D1 × P4).
        #expect(vault.actions.contains { $0.project == Fixtures.flatProject.id })
    }

    @Test func completingTheLastOpenActionMakesAProjectStalled() throws {
        let env = Fixtures.reducerEnv()
        let vault = Fixtures.sampleSnapshot
        let erasmus = Fixtures.erasmusProject
        #expect(!Rules.isStalled(erasmus, in: vault, today: env.today))

        let action = try #require(vault.actions.first { $0.project == erasmus.id && !$0.status.isClosed })
        let result = try Reducer.reduce(vault, .complete(action.id), env: env)
        #expect(Rules.stalledProjects(result.snapshot, today: env.today).map(\.id).contains(erasmus.id))
        #expect(result.prompts == [.whatsNext(project: erasmus.id)])
    }
}
