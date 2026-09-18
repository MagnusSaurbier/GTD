import Testing
import Foundation
import GTDModel
import GTDFixtures
import GTDAppCore
@testable import FeatureSettings

/// Drives `SettingsSession` through `AppModel` + `InMemoryBackend`, the same integration style
/// `AppModelAcceptanceTests` uses — proves the settings edits actually reach the snapshot via
/// `GTDCommand`, not just the pure `ContextsEditing` helpers.
@MainActor
struct SettingsSessionTests {
    private func makeSession() -> SettingsSession {
        let backend = InMemoryBackend(snapshot: Fixtures.sampleSnapshot, deviceID: "test")
        let model = AppModel(backend: backend, snapshot: Fixtures.sampleSnapshot, today: { Fixtures.today })
        return SettingsSession(model: model)
    }

    @Test func addContextReachesTheSnapshot() async throws {
        let session = makeSession()
        try await session.addContext("outdoors")
        #expect(session.config.contexts.contains("outdoors"))
    }

    @Test func renameAndRemoveContextGoThroughUpdateConfig() async throws {
        let session = makeSession()
        try await session.renameContext("phone", to: "mobile")
        #expect(session.config.contexts.contains("mobile"))
        #expect(!session.config.contexts.contains("phone"))

        try await session.removeContext("mobile")
        #expect(!session.config.contexts.contains("mobile"))
    }

    @Test func toggleOnTheGoIsReflectedImmediately() async throws {
        let session = makeSession()
        #expect(!session.config.onTheGoContexts.contains("deep-work"))
        try await session.toggleOnTheGo("deep-work")
        #expect(session.config.onTheGoContexts.contains("deep-work"))
    }

    @Test func reorderContextsChangesTheOrder() async throws {
        let session = makeSession()
        let first = session.config.contexts[0]
        try await session.reorderContexts(from: IndexSet(integer: 0), to: 2)
        #expect(session.config.contexts[1] == first)
    }

    @Test func setNextCapUpdatesTheConfig() async throws {
        let session = makeSession()
        try await session.setNextCap(20)
        #expect(session.config.nextCap == 20)
    }

    @Test func setNextCapRejectsZeroOrBelow() async throws {
        let session = makeSession()
        await #expect(throws: GTDError.invalid("Next cap must be at least 1")) {
            try await session.setNextCap(0)
        }
        #expect(session.config.nextCap == GTDConfig.default.nextCap)
    }

    @Test func setRoutineTimeReachesTheRoutine() async throws {
        let session = makeSession()
        let routine = try #require(session.routines.first)
        try await session.setRoutineTime(routine.id, to: DayTime(hour: 6, minute: 30))
        #expect(session.routines.first { $0.id == routine.id }?.time == DayTime(hour: 6, minute: 30))

        try await session.setRoutineTime(routine.id, to: nil)
        #expect(session.routines.first { $0.id == routine.id }?.time == nil)
    }

    @Test func affectedActionCountMatchesTheSnapshot() {
        let session = makeSession()
        #expect(session.affectedActionCount(for: "mac") ==
            ContextsEditing.affectedActionCount(for: "mac", in: Fixtures.sampleSnapshot.actions))
    }
}
