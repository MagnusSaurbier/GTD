import XCTest
import GTDModel
import GTDFixtures
import GTDIntents
import GTDNotifications
import FeatureSettings
@testable import GTD

/// Unit tests for the shell's own logic. Everything with GTD meaning is tested in the package;
/// what is left here is routing, the device id and the settings mapping — the three places where
/// the app shell can be wrong on its own.
final class AppRouteTests: XCTestCase {

    func testParsesEveryDeepLinkTheAppCanReceive() {
        XCTAssertEqual(AppRoute(url: "gtd://inbox"), .processInbox)
        XCTAssertEqual(AppRoute(url: InboxDeepLink.url), .processInbox)
        XCTAssertEqual(AppRoute(url: "gtd://waiting"), .waiting)
        XCTAssertEqual(
            AppRoute(url: "gtd://action/Actions/Call%20bank.md"),
            .action(NoteID(path: "Actions/Call%20bank.md")))
        XCTAssertEqual(
            AppRoute(url: NotificationRoute.action(NoteID(path: "Actions/Call bank.md")).url),
            .action(NoteID(path: "Actions/Call bank.md")))
        XCTAssertEqual(
            AppRoute(url: RoutineDeepLink.url(forRoutineTitled: "Morning")),
            .routine(NoteID(path: "GTD/Routines/Morning.md")))
    }

    func testRejectsAnythingItDoesNotUnderstand() {
        XCTAssertNil(AppRoute(url: ""))
        XCTAssertNil(AppRoute(url: "https://example.com"))
        XCTAssertNil(AppRoute(url: "gtd://elsewhere"))
    }

    /// T30 gotcha #3: a deep link's routine path is built from `VaultLayout.default`, so a vault
    /// with a different routines folder must still resolve — by title.
    func testResolvesARoutineByTitleWhenThePathDoesNotMatch() {
        var snapshot = Fixtures.sampleSnapshot
        let moved = NoteID(path: "GTD/Rituals/Morning.md")
        snapshot.routines = [Routine(id: moved, title: "Morning", time: nil, steps: [])]

        let linked = NoteID(path: "GTD/Routines/Morning.md")
        XCTAssertEqual(AppRoute.resolveRoutine(linked, in: snapshot)?.id, moved)
        XCTAssertNil(AppRoute.resolveRoutine(NoteID(path: "GTD/Routines/Nope.md"), in: snapshot))
    }
}

@MainActor
final class AppRouterTests: XCTestCase {

    func testProcessInboxRouteOpensTheInboxOnBothPlatforms() {
        let router = AppRouter()
        router.apply(.processInbox, snapshot: Fixtures.sampleSnapshot)
        XCTAssertEqual(router.tab, .inbox)
        XCTAssertTrue(router.isProcessingInbox)
        XCTAssertEqual(router.overview.selection, .inbox)
    }

    func testAnActionRouteOnlyNavigatesToNotesThatExist() {
        let router = AppRouter()
        let snapshot = Fixtures.sampleSnapshot
        let existing = snapshot.actions[0].id

        router.apply(.action(existing), snapshot: snapshot)
        XCTAssertEqual(router.nextPath, [existing])
        XCTAssertEqual(router.overview.detail, .action(existing))

        router.apply(.action(NoteID(path: "Actions/Ghost.md")), snapshot: snapshot)
        XCTAssertEqual(router.nextPath, [existing], "a note that is gone is not pushed")
    }

    func testARoutineRouteOpensTheRunner() {
        let router = AppRouter()
        let snapshot = Fixtures.sampleSnapshot
        let routine = snapshot.routines[0]

        router.apply(.routine(routine.id), snapshot: snapshot)
        XCTAssertEqual(router.tab, .routines)
        XCTAssertEqual(router.routineRun?.note, routine.id)
        XCTAssertTrue(router.isFlowPresented)
    }

    func testAPendingRouteIsConsumedOnce() {
        let store = InMemoryPendingRouteStore()
        let pending = PendingRoute(store: store)
        pending.set(InboxDeepLink.url)

        let router = AppRouter()
        router.consumePendingRoute(pending, snapshot: Fixtures.sampleSnapshot)
        XCTAssertTrue(router.isProcessingInbox)

        router.isProcessingInbox = false
        router.consumePendingRoute(pending, snapshot: Fixtures.sampleSnapshot)
        XCTAssertFalse(router.isProcessingInbox, "a route is delivered at most once")
    }

    func testPruningDropsNotesThatLeftTheVault() {
        let router = AppRouter()
        let snapshot = Fixtures.sampleSnapshot
        router.nextPath = [snapshot.actions[0].id, NoteID(path: "Actions/Ghost.md")]
        router.routineRun = NoteTarget(NoteID(path: "GTD/Routines/Ghost.md"))

        router.prune(against: snapshot)

        XCTAssertEqual(router.nextPath, [snapshot.actions[0].id])
        XCTAssertNil(router.routineRun)
    }
}

@MainActor
final class ShellSupportTests: XCTestCase {

    func testDeviceIdIsFileNameSafeAndStable() {
        XCTAssertEqual(DeviceIdentity.sanitize("Magnus’ MacBook Pro.local"), "Magnus-MacBook-Pro-local")
        XCTAssertEqual(DeviceIdentity.sanitize("--"), "")
        XCTAssertFalse(DeviceIdentity.make(hostName: "").isEmpty)
        XCTAssertFalse(DeviceIdentity.make(hostName: "iPhone.local").contains("."))

        let defaults = UserDefaults(suiteName: "gtd.tests.\(UUID().uuidString)")!
        let first = DeviceIdentity.resolve(defaults: defaults)
        XCTAssertEqual(first, DeviceIdentity.resolve(defaults: defaults))
    }

    /// A kind with no stored answer is on — the same default the settings toggles show.
    func testNotificationSettingsMapping() {
        var device = DeviceSettings.default
        XCTAssertEqual(
            NotificationService.settings(from: device).enabledKinds,
            Set(NotificationKind.allCases))

        device.notificationKinds[NotificationKind.summary.rawValue] = false
        device.morningTime = DayTime(hour: 6, minute: 30)
        let mapped = NotificationService.settings(from: device)
        XCTAssertFalse(mapped.enabledKinds.contains(.summary))
        XCTAssertTrue(mapped.enabledKinds.contains(.routineStart))
        XCTAssertEqual(mapped.morningTime, DayTime(hour: 6, minute: 30))
    }

    func testFixturesLaunchArgument() {
        XCTAssertFalse(LaunchOptions.useFixtures, "the test host is launched without it")
    }
}
