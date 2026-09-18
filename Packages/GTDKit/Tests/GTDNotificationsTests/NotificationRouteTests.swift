import Testing
import GTDModel
@testable import GTDNotifications

/// `gtd://…` deep-link round trip, used by notification taps and parsed back by T40.
struct NotificationRouteTests {
    @Test func actionRoundTrips() {
        let route = NotificationRoute.action(NoteID(path: "Actions/Call dentist.md"))
        #expect(NotificationRoute(url: route.url) == route)
        #expect(route.url == "gtd://action/Actions/Call dentist.md")
    }

    @Test func routineRoundTrips() {
        let route = NotificationRoute.routine(NoteID(path: "GTD/Routines/Morning.md"))
        #expect(NotificationRoute(url: route.url) == route)
        #expect(route.url == "gtd://routine/GTD/Routines/Morning.md")
    }

    @Test func waitingRoundTrips() {
        #expect(NotificationRoute(url: NotificationRoute.waiting.url) == .waiting)
        #expect(NotificationRoute.waiting.url == "gtd://waiting")
    }

    @Test func unknownSchemesAndPathsAreRejected() {
        #expect(NotificationRoute(url: "https://example.com") == nil)
        #expect(NotificationRoute(url: "gtd://") == nil)
        #expect(NotificationRoute(url: "gtd://something-else") == nil)
        #expect(NotificationRoute(url: "") == nil)
    }
}
