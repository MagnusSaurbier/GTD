import Testing
import Foundation
@testable import GTDNotifications

/// A fake `NotificationCenterPort` so the scheduler's diffing logic is tested without
/// `UNUserNotificationCenter` (unavailable in this build-out container — see ARCHITECTURE §5).
private actor FakePort: NotificationCenterPort {
    private(set) var pending: Set<String> = []
    private(set) var addedIDs: [String] = []
    private(set) var removedIDs: [String] = []
    private(set) var authorizationRequests = 0
    var authorizationResult: Result<Bool, Error> = .success(true)

    func seed(_ ids: [String]) { pending.formUnion(ids) }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return try authorizationResult.get()
    }

    func pendingIdentifiers() async -> [String] { Array(pending) }

    func add(_ notification: PlannedNotification) async throws {
        pending.insert(notification.id)
        addedIDs.append(notification.id)
    }

    func remove(identifiers: [String]) async {
        for id in identifiers { pending.remove(id) }
        removedIDs.append(contentsOf: identifiers)
    }
}

private func notification(_ id: String) -> PlannedNotification {
    PlannedNotification(
        id: id, kind: .followUp, title: "T", body: "B", fireDate: Date(), deepLink: "")
}

struct NotificationSchedulerTests {
    struct Failure: Error {}

    @Test func firstSyncFromEmptyAddsEverything() async throws {
        let port = FakePort()
        let scheduler = NotificationScheduler(center: port)
        try await scheduler.sync(planned: [notification("a"), notification("b")])

        let added = await port.addedIDs
        let removed = await port.removedIDs
        #expect(Set(added) == ["a", "b"])
        #expect(removed.isEmpty)
        #expect(await Set(port.pendingIdentifiers()) == ["a", "b"])
    }

    @Test func onlyTheDeltaIsAppliedAddsAndRemovesSeparately() async throws {
        let port = FakePort()
        await port.seed(["keep", "stale"])
        let scheduler = NotificationScheduler(center: port)

        try await scheduler.sync(planned: [notification("keep"), notification("new")])

        let added = await port.addedIDs
        let removed = await port.removedIDs
        #expect(added == ["new"])
        #expect(removed == ["stale"])
        #expect(await Set(port.pendingIdentifiers()) == ["keep", "new"])
    }

    @Test func repeatingTheSamePlanIsANoOp() async throws {
        let port = FakePort()
        let scheduler = NotificationScheduler(center: port)
        let plan = [notification("a"), notification("b")]
        try await scheduler.sync(planned: plan)
        try await scheduler.sync(planned: plan)

        let added = await port.addedIDs
        let removed = await port.removedIDs
        #expect(added == ["a", "b"])   // only once, on the first sync
        #expect(removed.isEmpty)
    }

    @Test func emptyPlanRemovesEverythingPending() async throws {
        let port = FakePort()
        await port.seed(["a", "b"])
        let scheduler = NotificationScheduler(center: port)

        try await scheduler.sync(planned: [])

        #expect(await Set(port.removedIDs) == ["a", "b"])
        #expect(await port.pendingIdentifiers().isEmpty)
    }

    @Test func requestAuthorizationDelegatesToThePort() async throws {
        let port = FakePort()
        await port.setAuthorizationResult(.success(true))
        let scheduler = NotificationScheduler(center: port)
        let granted = try await scheduler.requestAuthorization()
        #expect(granted)
        #expect(await port.authorizationRequests == 1)
    }

    @Test func requestAuthorizationPropagatesARefusal() async throws {
        let port = FakePort()
        await port.setAuthorizationResult(.success(false))
        let scheduler = NotificationScheduler(center: port)
        let granted = try await scheduler.requestAuthorization()
        #expect(!granted)
    }

    @Test func requestAuthorizationPropagatesAThrownError() async throws {
        let port = FakePort()
        await port.setAuthorizationResult(.failure(Failure()))
        let scheduler = NotificationScheduler(center: port)
        await #expect(throws: Failure.self) {
            try await scheduler.requestAuthorization()
        }
    }
}

private extension FakePort {
    func setAuthorizationResult(_ result: Result<Bool, Error>) {
        authorizationResult = result
    }
}
