import Testing
@testable import GTDIntents

@Suite("PendingRoute — hand-off from a background intent to the foregrounded app")
struct PendingRouteTests {

    @Test func consumeReturnsWhatWasSetExactlyOnce() {
        let store = InMemoryPendingRouteStore()
        let route = PendingRoute(store: store)

        #expect(route.consume() == nil)
        route.set("gtd://routine/GTD/Routines/Morning.md")
        #expect(route.consume() == "gtd://routine/GTD/Routines/Morning.md")
        #expect(route.consume() == nil)
    }

    @Test func aSecondSetReplacesTheFirst() {
        let store = InMemoryPendingRouteStore()
        let route = PendingRoute(store: store)

        route.set("gtd://inbox")
        route.set("gtd://routine/GTD/Routines/Bedtime.md")
        #expect(route.consume() == "gtd://routine/GTD/Routines/Bedtime.md")
    }

    @Test func differentKeysDoNotCollide() {
        let store = InMemoryPendingRouteStore()
        let a = PendingRoute(store: store, key: "a")
        let b = PendingRoute(store: store, key: "b")

        a.set("gtd://inbox")
        #expect(b.consume() == nil)
        #expect(a.consume() == "gtd://inbox")
    }
}
