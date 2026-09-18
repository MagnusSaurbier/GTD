import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureProjects

@MainActor
struct WhatsNextModelTests {

    private func makeModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test", env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    @Test func openStepsPairEachStepWithItsFullListIndex() {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        // Steps 0 and 1 are already done/promoted in the fixture.
        #expect(next.openSteps.map(\.stepIndex) == [2, 3])
        #expect(next.openSteps.map(\.step.text) == [
            "Ask Prof. Weber for a reference", "Submit the online form",
        ])
    }

    @Test func titleReadsTheProjectsTitle() {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        #expect(next.title == "DAAD")
    }

    @Test func isStalledMatchesRules() {
        let model = makeModel()
        let stalled = WhatsNextModel(project: Fixtures.flatProject.id, model: model)
        let active = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        #expect(stalled.isStalled == true)
        #expect(active.isStalled == false)
    }

    @Test func promoteCreatesANextActionOneTap() async throws {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        let outcome = try await next.promote(stepIndex: 2)
        #expect(outcome == .success)
        let step = model.snapshot.project(Fixtures.daadProject.id)?.steps[2]
        #expect(step?.promotedTo != nil)
        let created = try #require(model.snapshot.action(step!.promotedTo!))
        #expect(created.title == "Ask Prof. Weber for a reference")
        #expect(created.status == .next)
    }

    /// The explicit cap-error path required by the brief, from the "What's next?" flow.
    @Test func promoteReachesTheCapThenFallsBackToBacklog() async throws {
        let model = makeModel()
        let cap = model.snapshot.config.nextCap
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)

        #expect(try await next.promote(stepIndex: 2) == .success)
        #expect(Rules.countsTowardCap(model.snapshot) == cap)

        let refused = try await next.promote(stepIndex: 3)
        #expect(refused == .capReached(cap: cap))
        #expect(model.snapshot.project(Fixtures.daadProject.id)?.steps[3].promotedTo == nil)

        let fallback = try await next.promoteToBacklog(stepIndex: 3)
        #expect(fallback == .success)
        let step = model.snapshot.project(Fixtures.daadProject.id)?.steps[3]
        let created = try #require(model.snapshot.action(step!.promotedTo!))
        #expect(created.status == .backlog)
    }

    @Test func createActionAttachesTheFreeTextTitleToTheProject() async throws {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        let outcome = try await next.createAction(title: "Print the application form")
        #expect(outcome == .success)
        let created = try #require(model.snapshot.actions.first { $0.title == "Print the application form" })
        #expect(created.project == Fixtures.daadProject.id)
        #expect(created.status == .next)
    }

    @Test func createActionIgnoresBlankTitle() async throws {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        let before = model.snapshot.actions.count
        #expect(try await next.createAction(title: "   ") == .success)
        #expect(model.snapshot.actions.count == before)
    }

    @Test func markDoneSetsTheProjectStatusDone() async throws {
        let model = makeModel()
        let next = WhatsNextModel(project: Fixtures.daadProject.id, model: model)
        try await next.markDone()
        #expect(model.snapshot.project(Fixtures.daadProject.id)?.status == .done)
    }
}
