import Testing
@testable import DesignSystem

/// STYLEGUIDE §3.6 — the Knowledge/List navbar's fixed slots: `Knowledge` first, favourites in
/// order, `More…` last, clipped to the platform limit (4 on iPhone, 8 on Mac). Pure model, no
/// SwiftUI, so it is tested directly rather than through a view.
struct NavbarLayoutTests {

    @Test func knowledgeIsAlwaysFirstAndMoreIsAlwaysLast() {
        let slots = NavbarLayout.slots(favourites: ["Read", "Watch"], platform: .iPhone)
        #expect(slots.first?.kind == .knowledge)
        #expect(slots.last?.kind == .more)
    }

    @Test func favouritesAppearInTheGivenOrderNeverResorted() {
        let slots = NavbarLayout.slots(favourites: ["Wish", "Read", "Watch"], platform: .mac)
        let names = slots.compactMap { slot -> String? in
            if case let .list(name) = slot.kind { return name }
            return nil
        }
        #expect(names == ["Wish", "Read", "Watch"])
    }

    @Test func iPhoneClipsFavouritesAtFour() {
        let favourites = ["A", "B", "C", "D", "E", "F"]
        let slots = NavbarLayout.slots(favourites: favourites, platform: .iPhone)
        let listSlots = slots.filter { if case .list = $0.kind { true } else { false } }
        #expect(listSlots.count == 4)
        // Knowledge + 4 favourites + More… = 6 slots total.
        #expect(slots.count == 6)
    }

    @Test func macClipsFavouritesAtEight() {
        let favourites = (1...10).map { "List \($0)" }
        let slots = NavbarLayout.slots(favourites: favourites, platform: .mac)
        let listSlots = slots.filter { if case .list = $0.kind { true } else { false } }
        #expect(listSlots.count == 8)
    }

    @Test func keyIndicesFollowTheStyleguideTable() {
        // Knowledge = 1, favourites = 2…9, More… = 0 (STYLEGUIDE §3.6).
        let slots = NavbarLayout.slots(favourites: ["Read", "Watch", "Wish"], platform: .mac)
        #expect(slots.map(\.keyIndex) == [1, 2, 3, 4, 0])
    }

    @Test func zeroFavouritesStillShowsKnowledgeAndMore() {
        let slots = NavbarLayout.slots(favourites: [], platform: .iPhone)
        #expect(slots.map(\.kind) == [.knowledge, .more])
    }

    /// Break-proof: a naive `favourites.prefix(favourites.count)` (no real clipping) would let a
    /// 6th list slip onto the iPhone navbar. This is the assertion that would fail if the clip
    /// were dropped from `NavbarLayout.slots`.
    @Test func clippingIsNotOptional() {
        let slots = NavbarLayout.slots(favourites: ["A", "B", "C", "D", "E"], platform: .iPhone)
        #expect(slots.count < 7)
    }
}
