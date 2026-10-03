import Testing
import Foundation
import GTDModel
import GTDAppCore
import FeatureInbox
import GTDFixtures
@testable import FeatureReview

/// #94 — the review's card over a deferred item keeps what was typed (card fields and the
/// `System fix` line) when the review is left, and gives it back when the item comes up again.
@MainActor
struct DeferredCardDraftTests {

    @Test func aCardLeftHalfFilledComesBackAndFilingClearsIt() async throws {
        let model = ReviewTest.model()
        let session = ReviewTest.session(model: model)
        let item = try #require(session.currentDeferredItem)
        #expect(session.keptDeferredCard(for: item) == nil)

        var card = DeferredCardDraft(opening: item)
        card.draft.what = "Block 60 minutes to decide"
        card.systemFix = "Give decisions their own queue"
        session.keepDeferredCard(card, for: item)

        // A new review session (the review was left, the app quit) finds it.
        let again = ReviewTest.session(model: model)
        #expect(again.keptDeferredCard(for: item) == card)
        #expect(model.snapshot.inboxItem(item.id)?.body == item.body, "nothing written to the note")

        let decision = try #require(DeferredSweep.decision(target: .someday, draft: card.draft))
        model.inputDrafts.keep(WaitingSheetDraft(who: "Marie"), for: again.deferredWaitingDraftKey(for: item))
        await again.fileDeferred(item, decision: decision, systemFix: card.systemFix)
        #expect(again.keptDeferredCard(for: item) == nil)
        #expect(!model.inputDrafts.hasDraft(for: again.deferredWaitingDraftKey(for: item)))
    }

    @Test func anUntouchedCardKeepsNothing() throws {
        let model = ReviewTest.model()
        let session = ReviewTest.session(model: model)
        let item = try #require(session.currentDeferredItem)
        session.keepDeferredCard(DeferredCardDraft(opening: item), for: item)
        #expect(!model.inputDrafts.hasDraft(for: InputDraftKey.reviewDeferred(item.id)))
    }
}
