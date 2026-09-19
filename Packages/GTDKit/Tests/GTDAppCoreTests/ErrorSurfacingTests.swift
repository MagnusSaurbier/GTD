import Testing
import Foundation
import GTDModel
@testable import GTDAppCore

/// T41: a command the person asked for that quietly does nothing is a lying UI (STYLEGUIDE §1).
/// `perform`/`report` are the honest replacement for `try? await send(…)` at a call site that
/// has no flow of its own for the refusal: the error lands in `lastError`, which the app shell
/// shows in one alert.
@MainActor
struct ErrorSurfacingTests {

    /// A vault built here rather than taken from the fixtures, so the only thing that can
    /// refuse the command under test is the cap.
    private func modelAtCap() -> AppModel {
        var snapshot = VaultSnapshot.empty
        snapshot.actions = (1...15).map {
            Action(id: NoteID(path: "Actions/Next \($0).md"), title: "Next \($0)", status: .next)
        } + [Action(id: NoteID(path: "Actions/Spare.md"), title: "Spare", status: .backlog)]
        return AppModel(backend: InMemoryBackend(snapshot: snapshot), snapshot: snapshot)
    }

    private var spare: NoteID { NoteID(path: "Actions/Spare.md") }

    @Test func aRefusedCommandLandsInLastErrorInsteadOfVanishing() async throws {
        let model = modelAtCap()
        #expect(Rules.countsTowardCap(model.snapshot) == 15)
        let victim = try #require(model.snapshot.action(spare))

        let ok = await model.perform(.setStatus(victim.id, .next, waiting: nil))
        #expect(ok == false)
        #expect(model.lastError as? GTDError == .nextCapReached(cap: 15))
        #expect(model.snapshot.action(victim.id)?.status == .backlog, "and nothing moved")
    }

    @Test func aCommandThatGoesThroughClearsTheLastError() async throws {
        let model = modelAtCap()
        let victim = try #require(model.snapshot.action(spare))
        _ = await model.perform(.setStatus(victim.id, .next, waiting: nil))
        #expect(model.lastError != nil)

        let ok = await model.perform(.setStatus(victim.id, .maybe, waiting: nil))
        #expect(ok)
        #expect(model.lastError == nil)
        #expect(model.snapshot.action(victim.id)?.status == .maybe)
    }

    @Test func waitingWithoutTheWhoIsReportedToo() async throws {
        let model = modelAtCap()
        let victim = try #require(model.snapshot.action(spare))
        let ok = await model.perform(.setStatus(victim.id, .waiting, waiting: nil))
        #expect(ok == false)
        #expect(model.lastError as? GTDError == .waitingInfoRequired)
    }

    /// `report` is the same rule one level up, for a feature model's own throwing method.
    @Test func reportCarriesAnErrorOutOfAMultiCommandFlow() async throws {
        let model = modelAtCap()
        let victim = try #require(model.snapshot.action(spare))

        let ok = await model.report {
            try await model.send(.setStatus(victim.id, .maybe, waiting: nil))
            try await model.send(.setStatus(victim.id, .next, waiting: nil))   // refused: at cap
        }
        #expect(ok == false)
        #expect(model.lastError as? GTDError == .nextCapReached(cap: 15))
        #expect(model.snapshot.action(victim.id)?.status == .maybe,
                "the first command stands — `report` shows the failure, it does not roll back")
    }
}
