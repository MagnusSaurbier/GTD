import Testing
import Foundation
import DesignSystem
@testable import FeatureSettings

/// Pure client-side favourites math (L2, R-5, I4b): the reducer/`GTDCommand.setFavouriteLists`
/// has no count limit — this is what caps it at what the Mac navbar can show, and what the
/// iPhone-vs-Mac split of that stored order is.
struct ListsEditingTests {
    @Test func storageLimitMatchesTheMacNavbarLimit() {
        #expect(ListsEditing.storageLimit == NavbarPlatform.mac.favouriteLimit)
        #expect(ListsEditing.storageLimit == 8)
    }

    @Test func togglingAddsAnAbsentName() throws {
        let next = try ListsEditing.toggling("Watch", in: ["Read"])
        #expect(next == ["Read", "Watch"])
    }

    @Test func togglingRemovesAPresentNameCaseInsensitively() throws {
        let next = try ListsEditing.toggling("read", in: ["Read", "Watch"])
        #expect(next == ["Watch"])
    }

    @Test func togglingRefusesPastTheLimit() {
        let full = (1...8).map { "List\($0)" }
        #expect(throws: ListsEditing.FavouriteError.limitReached(8)) {
            try ListsEditing.toggling("List9", in: full)
        }
    }

    @Test func togglingAtExactlyOneUnderTheLimitStillSucceeds() throws {
        let almostFull = (1...7).map { "List\($0)" }
        let next = try ListsEditing.toggling("List8", in: almostFull, limit: 8)
        #expect(next.count == 8)
    }

    @Test func reorderingMovesAnItemForward() {
        let next = ListsEditing.reordering(["Read", "Watch", "Wish"], from: [0], to: 3)
        #expect(next == ["Watch", "Wish", "Read"])
    }

    @Test func reorderingMovesAnItemBackward() {
        let next = ListsEditing.reordering(["Read", "Watch", "Wish"], from: [2], to: 0)
        #expect(next == ["Wish", "Read", "Watch"])
    }

    @Test func isShownOnPhoneIsTrueOnlyForTheFirstFourSlots() {
        #expect(ListsEditing.isShownOnPhone(index: 0))
        #expect(ListsEditing.isShownOnPhone(index: 3))
        #expect(!ListsEditing.isShownOnPhone(index: 4))
        #expect(!ListsEditing.isShownOnPhone(index: 7))
    }
}
