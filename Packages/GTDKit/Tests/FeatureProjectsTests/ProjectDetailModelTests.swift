import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureProjects
import FeatureInbox

@MainActor
struct ProjectDetailModelTests {

    private func makeModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test", env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    // MARK: - Header

    @Test func setOutcomeAndWhyPersist() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        try await detail.setOutcome("New outcome text")
        try await detail.setWhy("New why text")
        #expect(detail.project?.outcome == "New outcome text")
        #expect(detail.project?.why == "New why text")
    }

    // MARK: - Area (R-7)

    /// The API T11's area picker drives: picking an area moves the project's folder, and the
    /// actions linked to it follow the note to its new path.
    @Test func settingAnAreaMovesTheProjectAndItsLinkedActions() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.flatProject.id, model: model)
        #expect(detail.area == nil)
        #expect(detail.areas.map(\.title) == ["Applications", "Karriereplanung"])

        let area = try #require(detail.areas.first { $0.title == "Karriereplanung" })
        try await detail.setArea(area.id)

        let moved = NoteID(path: "Projects/Karriereplanung/Wohnungssuche/Wohnungssuche.md")
        #expect(model.snapshot.project(moved)?.area == area.id)
        #expect(model.snapshot.project(Fixtures.flatProject.id) == nil)
        #expect(model.snapshot.actions.allSatisfy { $0.project != Fixtures.flatProject.id })
    }

    /// …and taking it away again puts the folder back in `Projects/no_area/` (R-6).
    @Test func clearingTheAreaMovesTheProjectIntoNoArea() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.thesisProject.id, model: model)
        #expect(detail.area?.title == "Karriereplanung")

        try await detail.setArea(nil)
        let moved = NoteID(path: "Projects/no_area/Masterarbeit/Masterarbeit.md")
        #expect(model.snapshot.project(moved)?.area == nil)
    }

    /// The refusal reaches the caller instead of being swallowed — the picker shows it (R-7).
    @Test func settingAnAreaThatAlreadyHoldsThatProjectNameIsRefused() async throws {
        var snapshot = Fixtures.sampleSnapshot
        // An area-less project whose name is taken inside `Applications`.
        snapshot.projects.append(Project(
            id: NoteID(path: "Projects/no_area/DAAD/DAAD.md"), title: "DAAD", status: .active))
        let model = makeModel(snapshot: snapshot)
        let detail = ProjectDetailModel(
            project: NoteID(path: "Projects/no_area/DAAD/DAAD.md"), model: model)

        await #expect(throws: GTDError.titleCollision("DAAD")) {
            try await detail.setArea(Fixtures.applicationsArea.id)
        }
        #expect(model.snapshot.project(NoteID(path: "Projects/no_area/DAAD/DAAD.md")) != nil)
    }

    // MARK: - Status and demotion (P3)

    @Test func demotionCountIsZeroWhenStayingActive() {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(detail.demotionCount(forChangingStatusTo: .active) == 0)
    }

    @Test func settingAProjectOffActiveDemotesItsNextActionsAndReportsTheCount() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let expectedCount = model.snapshot.actions
            .count { $0.project == Fixtures.daadProject.id && $0.status.countsTowardCap }
        #expect(expectedCount > 0)

        let demoted = try await detail.setStatus(.onHold)

        #expect(demoted == expectedCount)
        #expect(detail.project?.status == .onHold)
        #expect(model.snapshot.actions.allSatisfy {
            $0.project != Fixtures.daadProject.id || !$0.status.countsTowardCap
        })
    }

    // MARK: - Steps: add / edit / check

    @Test func addStepAppendsAnOpenStep() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let before = detail.steps.count
        try await detail.addStep("Book flights")
        #expect(detail.steps.count == before + 1)
        #expect(detail.steps.last == ProjectStep(text: "Book flights"))
    }

    @Test func addStepIgnoresBlankText() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let before = detail.steps.count
        try await detail.addStep("   ")
        #expect(detail.steps.count == before)
    }

    @Test func editStepChangesItsText() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        try await detail.editStep(at: 2, text: "Ask Prof. Weber this week")
        #expect(detail.steps[2].text == "Ask Prof. Weber this week")
    }

    @Test func toggleStepFlipsDone() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(detail.steps[2].done == false)
        try await detail.toggleStep(at: 2)
        #expect(detail.steps[2].done == true)
        try await detail.toggleStep(at: 2)
        #expect(detail.steps[2].done == false)
    }

    @Test func deleteStepRemovesOnlyThatStep() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        var expected = Fixtures.daadProject.steps.map(\.text)
        expected.remove(at: 2)
        try await detail.deleteStep(at: 2)
        #expect(detail.steps.map(\.text) == expected)
    }

    @Test func deleteStepOutOfRangeIsANoOp() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let before = detail.steps
        try await detail.deleteStep(at: before.count)
        #expect(detail.steps == before)
    }

    // MARK: - Steps: reorder (P6 — drag + ⌥↑↓)

    @Test func moveStepUpAndDownPersistTheNewOrder() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let originalTexts = detail.steps.map(\.text)

        try await detail.moveStepDown(at: 1)
        #expect(detail.steps.map(\.text) == StepReorder.moveDown(
            Fixtures.daadProject.steps, at: 1)!.map(\.text))

        try await detail.moveStepUp(at: 2)
        #expect(detail.steps.map(\.text) == originalTexts)   // back where it started
    }

    @Test func moveStepUpAtTheTopIsANoOpAndSendsNoCommand() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let before = model.snapshot
        try await detail.moveStepUp(at: 0)
        #expect(model.snapshot == before)   // nothing was sent, so the snapshot is untouched
    }

    @Test func dragReorderUpdatesTheFullStepArray() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        try await detail.moveStep(fromOffsets: [0], toOffset: detail.steps.count)
        #expect(detail.steps.first?.text == "Write motivation letter")
        #expect(detail.steps.last?.text == "Collect transcripts")
    }

    // MARK: - Promote (P6) — including the cap-error path

    @Test func promoteStepCreatesAnActionAndMarksTheStepPromoted() async throws {
        let model = makeModel()
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == model.snapshot.config.nextCap - 1)
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        // Steps 0 and 1 are already done/promoted in the fixture — 2 is the first open one.

        // R-3 — the promote form collects what Next requires; the model refuses without it.
        let outcome = try await detail.promoteStep(
            at: 2, draft: ActionDraft(
                title: "Ask Prof. Weber for a reference", status: .next,
                contexts: ["mac"], timeEstimate: 30, why: "The application needs it."))

        #expect(outcome == .success)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == model.snapshot.config.nextCap)
        #expect(detail.steps[2].promotedTo != nil)
        let created = try #require(model.snapshot.action(detail.steps[2].promotedTo!))
        #expect(created.status == .next)
        #expect(created.project == Fixtures.daadProject.id)
    }

    /// The brief's required case: promoting into a full Next hits the cap, and the caller can
    /// fall back to Someday — the simplified T22 version of T20's "Next is full" sheet.
    @Test func promotingIntoAFullNextReachesTheCapThenSucceedsToSomeday() async throws {
        let model = makeModel()
        let cap = model.snapshot.config.nextCap
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap - 1)
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)

        // First promotion fills the last Next slot (14 → 15). Steps 0 and 1 are already
        // done/promoted in the fixture, so 2 and 3 are the open ones.
        let first = try await detail.promoteStep(
            at: 2, draft: ActionDraft(
                title: "Ask Prof. Weber for a reference", status: .next,
                contexts: ["mac"], timeEstimate: 30, why: "The application needs it."))
        #expect(first == .success)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)

        // A second `.next` promotion is refused — never silently rerouted (I4, A3).
        let refused = try await detail.promoteStep(
            at: 3, draft: ActionDraft(
                title: "Submit the online form", status: .next,
                contexts: ["mac"], timeEstimate: 30, why: "The deadline is in October."))
        #expect(refused == .capReached(cap: cap))
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)          // vault untouched
        #expect(detail.steps[3].promotedTo == nil)                     // step still open

        // The offered fallback succeeds: send the same step to Someday instead.
        let fallback = try await detail.promoteStepToSomeday(
            at: 3, draft: ActionDraft(title: "Submit the online form", status: .next))
        #expect(fallback == .success)
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == cap)          // Someday doesn't count
        #expect(detail.steps[3].promotedTo != nil)
        let created = try #require(model.snapshot.action(detail.steps[3].promotedTo!))
        #expect(created.status == .someday)
    }

    // MARK: - Reference files and log (P6)

    @Test func referenceFilesAndLogComeFromTheProject() {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(detail.referenceFiles == Fixtures.daadProject.referenceFiles)
        #expect(detail.log.count == Fixtures.daadProject.log.count)
        // Most recent first.
        #expect(zip(detail.log, detail.log.dropFirst()).allSatisfy { $0.day >= $1.day })
    }

    @Test func activeActionsAreOnlyThisProjectsNextOrInProgressActions() {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(!detail.activeActions.isEmpty)
        #expect(detail.activeActions.allSatisfy { $0.project == Fixtures.daadProject.id && $0.status.countsTowardCap })
    }

    @Test func stalledMatchesRules() {
        let model = makeModel()
        let stalled = ProjectDetailModel(project: Fixtures.flatProject.id, model: model)
        let active = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(stalled.isStalled == true)
        #expect(active.isStalled == false)
    }

    // MARK: - One list of steps and actions (#76)

    /// Each step's badge: done → nothing, linked to an open action → its status, open → Promote.
    @Test func eachStepStandsWhereItsNoteIs() throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        #expect(detail.standing(of: detail.steps[0]) == .settled)
        let linked = try #require(detail.steps[1].promotedTo.flatMap { model.snapshot.action($0) })
        #expect(detail.standing(of: detail.steps[1]) == .action(linked))
        #expect(detail.standing(of: detail.steps[2]) == .promotable)
    }

    /// A step that points at another project is a subproject (`→ Project`).
    @Test func aStepLinkedToAProjectIsASubproject() throws {
        var snapshot = Fixtures.sampleSnapshot
        let sub = try #require(snapshot.projects.first { $0.id != Fixtures.daadProject.id })
        let index = try #require(snapshot.projects.firstIndex { $0.id == Fixtures.daadProject.id })
        snapshot.projects[index].steps.append(ProjectStep(text: sub.title, promotedTo: sub.id))
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: makeModel(snapshot: snapshot))
        #expect(detail.standing(of: detail.steps.last!) == .project(sub))
    }

    /// The Next items that no step links to join the list; linked ones appear only as their step.
    @Test func looseActionsAreTheActiveActionsNoStepLinks() {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let linked = Set(detail.steps.compactMap(\.promotedTo))
        #expect(detail.looseActions.allSatisfy { !linked.contains($0.id) })
        #expect(Set(detail.looseActions.map(\.id)).union(linked.intersection(Set(detail.activeActions.map(\.id))))
            == Set(detail.activeActions.map(\.id)))
    }

    /// `→ Next` opens the inbox card over the action; its Someday exit moves it and the step
    /// then reads `→ Someday`.
    @Test func theStatusCardChangesWhereTheStepStands() async throws {
        let model = makeModel()
        let detail = ProjectDetailModel(project: Fixtures.daadProject.id, model: model)
        let action = try #require(detail.steps[1].promotedTo.flatMap { model.snapshot.action($0) })
        let card = MakeActionModel(model: model, changingStatusOf: action)
        #expect(card.sheet == nil)
        #expect(card.missingFields.isEmpty)
        #expect(card.draft.why == action.why)

        await card.take(.someday)

        #expect(card.isFiled)
        let moved = try #require(model.snapshot.action(action.id))
        #expect(moved.status == .someday)
        #expect(detail.standing(of: detail.steps[1]) == .action(moved))
    }
}
