import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDAppCore

/// The T00 acceptance scenario (agent_task/00-foundation.md): file an inbox item to Next,
/// hit the cap, complete a project action and see the prompt, undo.
@MainActor
struct AppModelAcceptanceTests {

    private func makeModel() -> (AppModel, InMemoryBackend) {
        let backend = InMemoryBackend(
            snapshot: Fixtures.sampleSnapshot,
            deviceID: "test",
            env: { Fixtures.reducerEnv(deviceID: "test") })
        let model = AppModel(
            backend: backend,
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today })
        return (model, backend)
    }

    @Test func sampleVaultSitsOneBelowTheCap() {
        let snapshot = Fixtures.sampleSnapshot
        #expect(Rules.countsTowardCap(snapshot) == snapshot.config.nextCap - 1)
    }

    @Test func fileInboxToNextThenHitTheCapThenCompleteThenUndo() async throws {
        let (model, _) = makeModel()
        let cap = model.snapshot.config.nextCap
        let queue = Rules.inboxQueue(model.snapshot)
        #expect(queue.count >= 2)

        // 1. The first card fits: 14 → 15.
        try await model.send(.fileInbox(queue[0].id, .action(
            ActionDraft(title: "Call the Hausverwaltung", status: .next,
                        contexts: ["calls"], what: "Call about the window handle"))))
        #expect(Rules.countsTowardCap(model.snapshot) == cap)
        #expect(model.snapshot.inboxItem(queue[0].id) == nil)
        #expect(model.undoLabel == "Filed to Next")

        // 2. The second one is refused — never automatically re-routed (I4, A3).
        await #expect(throws: GTDError.nextCapReached(cap: cap)) {
            try await model.send(.fileInbox(queue[1].id, .action(
                ActionDraft(title: "Rename scanned pdfs", status: .next,
                            what: "Write the rename script"))))
        }
        #expect(Rules.countsTowardCap(model.snapshot) == cap)
        #expect(model.snapshot.inboxItem(queue[1].id) != nil)

        // 3. Completing a project action emits the "What's next?" prompt (P5).
        let projectAction = try #require(model.snapshot.actions.first {
            $0.project == Fixtures.daadProject.id && $0.status.countsTowardCap
        })
        let snapshotBeforeCompletion = model.snapshot
        try await model.send(.complete(projectAction.id))
        #expect(model.prompt == .whatsNext(project: Fixtures.daadProject.id))
        #expect(model.snapshot.action(projectAction.id)?.status == .done)
        #expect(model.snapshot.action(projectAction.id)?.completedDate != nil)
        #expect(model.snapshot.project(Fixtures.daadProject.id)?.log.count
                == snapshotBeforeCompletion.project(Fixtures.daadProject.id)!.log.count + 1)

        // 4. Undo puts it back (N6).
        await model.undo()
        #expect(model.snapshot.action(projectAction.id)?.status == projectAction.status)
        #expect(model.snapshot == snapshotBeforeCompletion)
        #expect(model.undoLabel == nil)
    }

    @Test func waitingRequiresWhoAndFollowUp() async throws {
        let (model, _) = makeModel()
        let action = try #require(model.snapshot.actions.first { $0.status == .backlog })
        await #expect(throws: GTDError.waitingInfoRequired) {
            try await model.send(.setStatus(action.id, .waiting, waiting: nil))
        }
        try await model.send(.setStatus(action.id, .waiting, waiting:
            WaitingInfo(who: "Herr Kramer", followUp: Fixtures.day(7))))
        #expect(model.snapshot.action(action.id)?.waitingFor == "Herr Kramer")
        #expect(model.snapshot.action(action.id)?.followUpDate == Fixtures.day(7))
    }

    @Test func streamDeliversTheCurrentSnapshotFirst() async throws {
        let backend = InMemoryBackend(snapshot: Fixtures.sampleSnapshot)
        var iterator = backend.snapshots().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == Fixtures.sampleSnapshot)
    }
}
