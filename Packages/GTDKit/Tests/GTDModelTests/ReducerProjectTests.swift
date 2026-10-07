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

    /// R-6/P1/D40 — a project with no area is not loose under `Projects/`; it lives in
    /// `Projects/no_area/`, and it still has no area.
    @Test func aProjectWithoutAnAreaLivesInTheNoAreaFolder() throws {
        let result = try Reducer.reduce(
            TestVault.snapshot(), .createProject(ProjectDraft(title: "Wohnungssuche")), env: env)
        #expect(result.snapshot.projects.first?.id.path
                == "Projects/no_area/Wohnungssuche/Wohnungssuche.md")
        #expect(result.snapshot.projects.first?.area == nil)
    }

    /// R-6 — `no_area` is the folder that holds the area-less projects, so it cannot also be an
    /// area. Case-insensitively, because the file system is.
    @Test func anAreaCannotBeCalledNoArea() {
        for spelling in ["no_area", "NO_AREA", "No_Area", " no_area "] {
            #expect(TestVault.error(TestVault.snapshot(), .createArea(title: spelling), env: env)
                    == .invalid("\"no_area\" is the folder for projects without an area "
                                + "and cannot be an area"),
                    "\(spelling) must be refused")
        }
        // …including through the "create the area alongside the project" path.
        #expect(TestVault.error(
            TestVault.snapshot(),
            .createProject(ProjectDraft(title: "Umzug", newAreaTitle: "no_area")), env: env)
                == .invalid("\"no_area\" is the folder for projects without an area "
                            + "and cannot be an area"))
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

    /// #53 — a project renamed or moved in Obsidian leaves the action's link dangling. Ticking
    /// the action off or editing it must still work; only a project the command *sets* must exist.
    @Test func aDanglingProjectLinkDoesNotBlockTheAction() throws {
        let ghost = NoteID(path: "Projects/Karriere/Manage&More 1/Manage&More.md")
        let vault = TestVault.snapshot(actions: [TestVault.action("Hackathon", .next, project: ghost)])
        let id = TestVault.actionID("Hackathon")

        let done = try Reducer.reduce(vault, .complete(id), env: env)
        #expect(done.snapshot.action(id)?.status == .done)
        #expect(done.snapshot.action(id)?.project == ghost)

        var edited = try #require(vault.action(id))
        edited.timeEstimate = 30
        #expect(TestVault.error(vault, .updateAction(edited), env: env) == nil)

        // Pointing an action at a project that does not exist is still refused.
        var moved = try #require(vault.action(id))
        moved.project = NoteID(path: "Projects/Nowhere/Nowhere.md")
        #expect(TestVault.error(vault, .updateAction(moved), env: env) == .notFound(moved.project!))
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

    /// The *title* half of the old refusal stands: the folder name is the project's identity.
    @Test func renamingAProjectIsStillRefused() {
        let project = TestVault.project("DAAD")
        let vault = TestVault.snapshot(projects: [project])

        var renamed = project
        renamed.title = "DAAD 2027"
        #expect(TestVault.error(vault, .updateProject(renamed), env: env)
                == .invalid("Renaming a project is not supported"))
    }

    // MARK: - R-7: changing a project's area moves its folder

    /// One command, one commit: the folder moves, the project note travels, every action's
    /// `project:` link follows it, and the renames say so.
    @Test func assigningAnAreaMovesTheProjectFolder() throws {
        let area = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        var project = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Write the letter", promotedTo: TestVault.actionID("Letter")),
        ])
        project.referenceFiles = ["Projects/no_area/DAAD/Transcript.pdf"]
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Letter", .next, project: project.id)],
            areas: [area],
            projects: [project])

        var moved = project
        moved.area = area.id
        let result = try Reducer.reduce(vault, .updateProject(moved), env: env)

        #expect(result.extraOps
                == [.moveFolder(from: "Projects/no_area/DAAD", to: "Projects/Wohnen/DAAD")])
        let newID = NoteID(path: "Projects/Wohnen/DAAD/DAAD.md")
        #expect(result.snapshot.projects[0].id == newID)
        #expect(result.snapshot.projects[0].area == area.id)
        #expect(result.snapshot.projects[0].referenceFiles == ["Projects/Wohnen/DAAD/Transcript.pdf"])
        // The action's `project:` wikilink is written from this id, so it is rewritten on disk.
        #expect(result.snapshot.actions[0].project == newID)
        #expect(result.snapshot.actions[0].status == .next, "an area change demotes nothing")
        // A promoted step points at an action in `Actions/`, which did not move.
        #expect(result.snapshot.projects[0].steps[0].promotedTo == TestVault.actionID("Letter"))
        // Both the project note and every file inside its folder, so open views follow.
        #expect(result.renames.pairs.map { ($0.old.path, $0.new.path) }.sorted { $0.0 < $1.0 }
                .map { [$0.0, $0.1] }
                == [["Projects/no_area/DAAD/DAAD.md", "Projects/Wohnen/DAAD/DAAD.md"],
                    ["Projects/no_area/DAAD/Transcript.pdf", "Projects/Wohnen/DAAD/Transcript.pdf"]])
    }

    /// Taking the area away puts the project back in `Projects/no_area/` (R-6).
    @Test func removingTheAreaMovesTheProjectIntoNoArea() throws {
        let area = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        let project = TestVault.project("Umzug", area: area.id)
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Kisten", .someday, project: project.id)],
            areas: [area], projects: [project])

        var moved = project
        moved.area = nil
        let result = try Reducer.reduce(vault, .updateProject(moved), env: env)

        #expect(result.extraOps
                == [.moveFolder(from: "Projects/Wohnen/Umzug", to: "Projects/no_area/Umzug")])
        let newID = NoteID(path: "Projects/no_area/Umzug/Umzug.md")
        #expect(result.snapshot.projects[0].id == newID)
        #expect(result.snapshot.projects[0].area == nil)
        #expect(result.snapshot.actions[0].project == newID)
    }

    /// R-6 — a project a pre-rework vault left directly under `Projects/` is never moved on its
    /// own, but giving it an area moves it out of there like any other project.
    @Test func aLegacyTopLevelProjectMovesOutOfTheProjectsRoot() throws {
        let area = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        let legacy = Project(
            id: NoteID(path: "Projects/Altbau/Altbau.md"), title: "Altbau", status: .active)
        let vault = TestVault.snapshot(areas: [area], projects: [legacy])

        var moved = legacy
        moved.area = area.id
        let result = try Reducer.reduce(vault, .updateProject(moved), env: env)

        #expect(result.extraOps
                == [.moveFolder(from: "Projects/Altbau", to: "Projects/Wohnen/Altbau")])
        #expect(result.snapshot.projects[0].id.path == "Projects/Wohnen/Altbau/Altbau.md")
    }

    /// Never overwrite: an area that already holds a project of this name refuses the move.
    @Test func movingOntoATakenFolderIsACollision() {
        let area = Area(id: TestVault.layout.areaPath(title: "Wohnen"), title: "Wohnen")
        let occupant = TestVault.project("Umzug", area: area.id)
        let project = TestVault.project("Umzug")
        let vault = TestVault.snapshot(areas: [area], projects: [occupant, project])

        var moved = project
        moved.area = area.id
        #expect(TestVault.error(vault, .updateProject(moved), env: env) == .titleCollision("Umzug"))
    }

    @Test func movingIntoAnUnknownAreaIsNotFound() {
        let project = TestVault.project("DAAD")
        let ghost = TestVault.layout.areaPath(title: "Ghost")
        var moved = project
        moved.area = ghost
        #expect(TestVault.error(TestVault.snapshot(projects: [project]), .updateProject(moved), env: env)
                == .notFound(ghost))
    }

    /// Editing anything else about a project still moves no folder and renames nothing.
    @Test func anEditThatLeavesTheAreaAloneMovesNothing() throws {
        let project = TestVault.project("DAAD")
        var edited = project
        edited.outcome = "Scholarship confirmed"
        let result = try Reducer.reduce(
            TestVault.snapshot(projects: [project]), .updateProject(edited), env: env)
        #expect(result.extraOps.isEmpty)
        #expect(result.renames.isEmpty)
        #expect(result.snapshot.projects[0].id == project.id)
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

    // MARK: - #61: linking an existing action as a step

    @Test func linkingAnActionAddsAStepAndSetsTheProject() throws {
        let project = TestVault.project("DAAD", steps: [ProjectStep(text: "Collect")])
        let action = TestVault.action("Book the language test")
        let result = try Reducer.reduce(
            TestVault.snapshot(actions: [action], projects: [project]),
            .linkStep(project: project.id, action: action.id), env: env)

        let steps = result.snapshot.projects[0].steps
        #expect(steps.count == 2)
        #expect(steps[1] == ProjectStep(text: "Book the language test", promotedTo: action.id))
        #expect(result.snapshot.action(action.id)?.project == project.id)
        #expect(result.snapshot.action(action.id)?.status == .someday)
    }

    @Test func linkingRefusesClosedForeignAndDuplicateActions() {
        let other = TestVault.project("Nebenjob")
        let done = TestVault.action("Done thing", .done, completed: -1)
        let foreign = TestVault.action("Foreign", project: other.id)
        let linked = TestVault.action("Linked")
        let project = TestVault.project("DAAD", steps: [ProjectStep(text: "Linked", promotedTo: linked.id)])
        let vault = TestVault.snapshot(actions: [done, foreign, linked], projects: [project, other])

        #expect(TestVault.error(vault, .linkStep(project: project.id, action: done.id), env: env)
                == .invalid("A finished action cannot become a step"))
        #expect(TestVault.error(vault, .linkStep(project: project.id, action: foreign.id), env: env)
                == .invalid("This action belongs to another project"))
        #expect(TestVault.error(vault, .linkStep(project: project.id, action: linked.id), env: env)
                == .invalid("This action is already a step of the project"))
        #expect(TestVault.error(vault, .linkStep(project: project.id, action: TestVault.actionID("Ghost")), env: env)
                == .notFound(TestVault.actionID("Ghost")))
    }

    @Test func aNextActionCannotBeLinkedToAnOnHoldProject() {
        let onHold = TestVault.project("Nebenjob", status: .onHold)
        let action = TestVault.action("Send CV", .next, contexts: ["mac"], timeEstimate: 30)
        #expect(TestVault.error(TestVault.snapshot(actions: [action], projects: [onHold]),
                                .linkStep(project: onHold.id, action: action.id), env: env)
                == .invalid("Only active projects put actions into Next"))
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
        // It has steps but no open action at all (P4).
        #expect(!Fixtures.flatProject.openSteps.isEmpty)
        #expect(!vault.actions.contains { $0.project == Fixtures.flatProject.id && !$0.status.isClosed })
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

/// #76 — every action added to a project becomes a linked step of that project's note.
struct ReducerProjectStepLinkTests {
    private let env = TestVault.env()

    private func vaultWithTwoProjects() throws -> (VaultSnapshot, Project, Project) {
        var vault = TestVault.snapshot()
        vault = try Reducer.reduce(vault, .createProject(ProjectDraft(title: "Umzug")), env: env).snapshot
        vault = try Reducer.reduce(vault, .createProject(ProjectDraft(title: "Steuer")), env: env).snapshot
        let umzug = try #require(vault.projects.first { $0.title == "Umzug" })
        let steuer = try #require(vault.projects.first { $0.title == "Steuer" })
        return (vault, umzug, steuer)
    }

    @Test func aNewActionInAProjectIsAppendedAsALinkedStep() throws {
        let (vault, umzug, _) = try vaultWithTwoProjects()
        let result = try Reducer.reduce(
            vault, .createAction(ActionDraft(title: "Kartons kaufen", status: .someday, project: umzug.id, what: "Do it")),
            env: env)
        let action = try #require(result.snapshot.actions.first { $0.title == "Kartons kaufen" })
        let steps = try #require(result.snapshot.project(umzug.id)?.steps)
        #expect(steps.last == ProjectStep(text: "Kartons kaufen", promotedTo: action.id))
        #expect(steps.filter { $0.promotedTo == action.id }.count == 1)
    }

    @Test func promotingAStepDoesNotAddASecondOne() throws {
        var (vault, umzug, _) = try vaultWithTwoProjects()
        let index = try #require(vault.projects.firstIndex { $0.id == umzug.id })
        vault.projects[index].steps = [ProjectStep(text: "Kartons kaufen")]
        let result = try Reducer.reduce(
            vault, .promoteStep(project: umzug.id, stepIndex: 0, ActionDraft(title: "", status: .someday)),
            env: env)
        #expect(result.snapshot.project(umzug.id)?.steps.count == 1)
    }

    @Test func changingTheProjectMovesTheOpenStep() throws {
        var (vault, umzug, steuer) = try vaultWithTwoProjects()
        vault = try Reducer.reduce(
            vault, .createAction(ActionDraft(title: "Belege sammeln", status: .someday, project: umzug.id, what: "Do it")),
            env: env).snapshot
        var action = try #require(vault.actions.first { $0.title == "Belege sammeln" })
        action.project = steuer.id
        let result = try Reducer.reduce(vault, .updateAction(action), env: env)
        #expect(result.snapshot.project(umzug.id)?.steps.contains { $0.promotedTo == action.id } == false)
        #expect(result.snapshot.project(steuer.id)?.steps.contains { $0.promotedTo == action.id } == true)
    }

    /// An unrelated command never writes into a project note: an action that was in the project
    /// without a step before stays without one.
    @Test func anUnrelatedEditLeavesALegacyActionAlone() throws {
        var (vault, umzug, _) = try vaultWithTwoProjects()
        vault = try Reducer.reduce(
            vault, .createAction(ActionDraft(title: "Alt", status: .someday, project: umzug.id, what: "Do it")),
            env: env).snapshot
        let index = try #require(vault.projects.firstIndex { $0.id == umzug.id })
        vault.projects[index].steps = []
        var action = try #require(vault.actions.first { $0.title == "Alt" })
        action.why = "Changed"
        let result = try Reducer.reduce(vault, .updateAction(action), env: env)
        #expect(result.snapshot.project(umzug.id)?.steps.isEmpty == true)
    }
}
