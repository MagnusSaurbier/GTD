import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDNotifications

/// Placeholder so the target builds and `swift test` has something to run.
/// **T13 replaces this with the real suite.**
struct GTDNotificationsPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func deepLinksRoundTrip() {
        let route = NotificationRoute.action(NoteID(path: "Actions/A.md"))
        #expect(NotificationRoute(url: route.url) == route)
        #expect(NotificationRoute(url: "gtd://waiting") == .waiting)
        #expect(NotificationRoute(url: "https://example.com") == nil)
    }

    @Test func plannerIsEmptyUntilT13() {
        #expect(NotificationPlanner.plan(snapshot: Fixtures.sampleSnapshot, now: Date()).isEmpty)
    }
}
