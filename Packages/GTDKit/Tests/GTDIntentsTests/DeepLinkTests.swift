import GTDModel
import Testing
@testable import GTDIntents

@Suite("RoutineDeepLink / InboxDeepLink (R3, I1)")
struct DeepLinkTests {

    @Test func matchesTheNotificationRouteFormatForADefaultLayout() {
        // Literal pinned to GTDNotificationsTests' `NotificationRoute(.routine(...))` case so a
        // pending route from this intent parses the same way as one from a notification tap.
        #expect(RoutineDeepLink.url(forRoutineTitled: "Morning") == "gtd://routine/GTD/Routines/Morning.md")
    }

    @Test func sanitizesTheTitleLikeVaultLayoutDoesEverywhereElse() {
        #expect(RoutineDeepLink.url(forRoutineTitled: "Evening: Wind-Down?")
                == "gtd://routine/GTD/Routines/Evening Wind-Down.md")
    }

    @Test func honoursACustomRoutinesFolder() {
        let layout = VaultLayout(routines: "00 Routines")
        #expect(RoutineDeepLink.url(forRoutineTitled: "Bedtime", layout: layout)
                == "gtd://routine/00 Routines/Bedtime.md")
    }

    @Test func inboxDeepLinkIsStable() {
        #expect(InboxDeepLink.url == "gtd://inbox")
    }
}
