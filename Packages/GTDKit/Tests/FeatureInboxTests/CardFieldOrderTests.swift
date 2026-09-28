import Testing
@testable import FeatureInbox

/// `⌘↩` / `⇧⌘↩` past a body field's input lines move focus along the card's fields
/// (STYLEGUIDE §4.4): title → (body) → `Why?` → `What?` and back.
@MainActor
@Suite("Card field order for ⌘↩ and ⇧⌘↩")
struct CardFieldOrderTests {
    @Test func commandReturnGoesFromWhyToWhatThenToTheCard() {
        #expect(InboxCardView.next(after: .why) == .what)
        #expect(InboxCardView.next(after: .what) == nil)
    }

    @Test func shiftCommandReturnGoesBackFromWhatToWhyToTheTitle() {
        #expect(InboxCardView.previous(before: .what, showsBody: false) == .why)
        #expect(InboxCardView.previous(before: .why, showsBody: false) == .text)
    }

    @Test func shiftCommandReturnFromWhyLandsOnTheBodyWhenTheCardShowsOne() {
        #expect(InboxCardView.previous(before: .why, showsBody: true) == .body)
    }

    @Test func shiftCommandReturnElsewhereKeepsTheFocus() {
        #expect(InboxCardView.previous(before: .notes, showsBody: true) == .notes)
        #expect(InboxCardView.previous(before: .text, showsBody: false) == .text)
    }
}
