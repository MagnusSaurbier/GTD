import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureProjects

@MainActor
struct ConvertToProjectModelTests {
    private let layout = VaultLayout.default

    private func makeModel(snapshot: VaultSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test", env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    /// A plain action with ≥ 2 checkboxes and no project (A2's trigger, `Rules.suggestsProject`).
    private var multiStepAction: Action {
        guard let action = Fixtures.sampleSnapshot.actions.first(where: { $0.title == "Prepare the lab presentation" }) else {
            fatalError("Fixture changed: expected an action named 'Prepare the lab presentation' with ≥ 2 checkboxes")
        }
        return action
    }

    // MARK: - Draft seeding (A2: title/why carried over, checkboxes become steps)

    @Test func makeDraftCarriesOverTitleWhyAndCheckboxesAsSteps() {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        let draft = convert.makeDraft()
        #expect(draft.title == "Prepare the lab presentation")
        #expect(draft.why == multiStepAction.why)
        #expect(draft.steps == ["Outline five slides", "Rehearse once out loud"])
    }

    @Test func suggestedStepsMatchTheActionsCheckboxes() {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        #expect(convert.suggestedSteps == ["Outline five slides", "Rehearse once out loud"])
    }

    @Test func projectIDMatchesTheLayoutFormula() {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        let draft = ProjectDraft(title: "Lab presentation")
        #expect(convert.projectID(for: draft) == layout.projectPath(title: "Lab presentation", inArea: nil))

        let withNewArea = ProjectDraft(title: "Lab presentation", newAreaTitle: "Teaching")
        #expect(convert.projectID(for: withNewArea)
            == layout.projectPath(title: "Lab presentation", inArea: layout.areaPath(title: "Teaching")))
    }

    // MARK: - Convert + first-step promotion (happy path)

    @Test func convertCreatesTheProjectAndTrashesTheOriginalAction() async throws {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        let draft = convert.makeDraft()

        let outcome = try await convert.convert(draft, promoteStepIndex: nil)

        #expect(outcome == .success)
        #expect(model.snapshot.action(multiStepAction.id) == nil)
        let project = model.snapshot.project(convert.projectID(for: draft))
        #expect(project?.steps.map(\.text) == draft.steps)
        #expect(project?.status == .active)
    }

    @Test func convertPromotesThePreSelectedFirstStep() async throws {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        let draft = convert.makeDraft()

        let outcome = try await convert.convert(draft, promoteStepIndex: 0)

        #expect(outcome == .success)
        let projectID = convert.projectID(for: draft)
        let project = try #require(model.snapshot.project(projectID))
        #expect(project.steps[0].promotedTo != nil)
        let created = try #require(model.snapshot.action(project.steps[0].promotedTo!))
        #expect(created.title == "Outline five slides")
        #expect(created.status == .next)
        #expect(created.project == projectID)
    }

    @Test func convertWithNoPromoteStepIndexLeavesAllStepsOpen() async throws {
        let model = makeModel(snapshot: Fixtures.sampleSnapshot)
        let convert = ConvertToProjectModel(action: multiStepAction.id, model: model)
        let draft = convert.makeDraft()

        _ = try await convert.convert(draft, promoteStepIndex: nil)

        let project = try #require(model.snapshot.project(convert.projectID(for: draft)))
        #expect(project.steps.allSatisfy { $0.promotedTo == nil })
    }

    // MARK: - Cap-error path on the post-conversion promotion (explicit, brief-required)

    private func makeCappedSnapshot() -> (VaultSnapshot, convertible: Action, filler: Action) {
        let filler = Action(id: layout.actionPath(title: "Filler"), title: "Filler", status: .next)
        let convertible = Action(
            id: layout.actionPath(title: "Two-step task"), title: "Two-step task", status: .backlog,
            what: "- [ ] Step one\n- [ ] Step two")
        let config = GTDConfig(contexts: [], onTheGoContexts: [], nextCap: 1, layout: layout)
        let snapshot = VaultSnapshot(actions: [filler, convertible], config: config)
        return (snapshot, convertible, filler)
    }

    @Test func promotingTheFirstStepAfterConvertCanReachTheCap() async throws {
        let (snapshot, convertible, _) = makeCappedSnapshot()
        let model = makeModel(snapshot: snapshot)
        let convert = ConvertToProjectModel(action: convertible.id, model: model)
        let draft = convert.makeDraft()
        #expect(draft.steps == ["Step one", "Step two"])

        let outcome = try await convert.convert(draft, promoteStepIndex: 0)

        #expect(outcome == .capReached(cap: 1))
        #expect(model.snapshot.action(convertible.id) == nil)   // conversion itself still happened
        let project = try #require(model.snapshot.project(convert.projectID(for: draft)))
        #expect(project.steps[0].promotedTo == nil)              // the promotion was refused
    }

    @Test func fallingBackToBacklogAfterTheCapSucceeds() async throws {
        let (snapshot, convertible, _) = makeCappedSnapshot()
        let model = makeModel(snapshot: snapshot)
        let convert = ConvertToProjectModel(action: convertible.id, model: model)
        let draft = convert.makeDraft()

        let capped = try await convert.convert(draft, promoteStepIndex: 0)
        #expect(capped == .capReached(cap: 1))

        let fallback = try await convert.promoteConvertedStepToBacklog(draft, stepIndex: 0)
        #expect(fallback == .success)

        let project = try #require(model.snapshot.project(convert.projectID(for: draft)))
        let created = try #require(model.snapshot.action(project.steps[0].promotedTo!))
        #expect(created.status == .backlog)
        #expect(Rules.countsTowardCap(model.snapshot) == 1)   // still just the filler
    }
}
