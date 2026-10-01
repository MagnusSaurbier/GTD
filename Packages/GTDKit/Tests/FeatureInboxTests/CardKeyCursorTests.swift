import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// The keyboard walk over the opened action card (#65): `⌘↩` from `What?` to the context chips,
/// the time chips and the outcome row; `Tab`/`⇧Tab` inside a row; `↩` toggles or presses; a
/// refused outcome sends the cursor to the first missing row.
@MainActor
struct CardKeyCursorTests {

    // MARK: - The pure walk

    @Test func theWalkGoesContextTimeDatesOutcomeAndStopsThere() {
        var cursor = CardKeyCursor.first(contextCount: 3)
        #expect(cursor == CardKeyCursor(row: .context, index: 0))
        cursor = cursor.advanced(contextCount: 3)
        #expect(cursor == CardKeyCursor(row: .time, index: 0))
        cursor = cursor.advanced(contextCount: 3)
        #expect(cursor == CardKeyCursor(row: .dates, index: 0), "#77: the date row after time")
        #expect(cursor.dateStop == .deferDate)
        cursor = cursor.advanced(contextCount: 3)
        #expect(cursor == CardKeyCursor(row: .outcome, index: 0))
        #expect(cursor.outcome == .next)
        #expect(cursor.advanced(contextCount: 3) == cursor, "the outcome row is the last one")
    }

    @Test func aVaultWithoutContextsStartsOnTheTimeRow() {
        #expect(CardKeyCursor.first(contextCount: 0) == CardKeyCursor(row: .time))
        #expect(CardKeyCursor.forMissing([.context, .timeEstimate], contextCount: 0)
            == CardKeyCursor(row: .time))
    }

    @Test func tabAndShiftTabWrapInsideTheRow() {
        let first = CardKeyCursor(row: .context, index: 0)
        #expect(first.moved(by: 1, contextCount: 3).index == 1)
        #expect(first.moved(by: -1, contextCount: 3).index == 2, "⇧Tab from the first wraps")
        #expect(CardKeyCursor(row: .context, index: 2).moved(by: 1, contextCount: 3).index == 0)
        let time = CardKeyCursor(row: .time, index: 3)
        #expect(time.moved(by: 1, contextCount: 3) == CardKeyCursor(row: .time, index: 0))
        #expect(time.timeBucket == .over60)
        let outcome = CardKeyCursor(row: .outcome, index: 4)
        #expect(outcome.outcome == .project)
        #expect(outcome.moved(by: 1, contextCount: 3).outcome == .next)
    }

    @Test func theDateRowReadsDeferDueProjectAndWraps() {
        #expect(CardDateStop.allCases == [.deferDate, .due, .project])
        let last = CardKeyCursor(row: .dates, index: 2)
        #expect(last.dateStop == .project)
        #expect(last.moved(by: 1, contextCount: 3).dateStop == .deferDate)
        #expect(CardKeyCursor(row: .time).dateStop == nil)
    }

    @Test func theOutcomeRowReadsNextSomedayWaitingDoneProject() {
        #expect(CardOutcome.allCases.map(\.title)
            == [Copy.next, Copy.someday, Copy.waiting, Copy.done, Copy.project])
        #expect(CardOutcome.allCases.map(\.exit) == [.next, .someday, .waiting, .done, nil])
    }

    @Test func aMissingTextFieldWinsOverAMissingChip() {
        #expect(CardKeyCursor.forMissing([.why, .context], contextCount: 3) == nil)
        #expect(CardKeyCursor.forMissing([.context, .timeEstimate], contextCount: 3)
            == CardKeyCursor(row: .context))
        #expect(CardKeyCursor.forMissing([.timeEstimate], contextCount: 3)
            == CardKeyCursor(row: .time))
        #expect(CardKeyCursor.forMissing([.followUpDate], contextCount: 3) == nil)
    }

    @Test func aShrunkContextRowPullsTheCursorBack() {
        #expect(CardKeyCursor(row: .context, index: 5).clamped(contextCount: 2).index == 1)
        #expect(CardKeyCursor(row: .context, index: 1).clamped(contextCount: 0)
            == CardKeyCursor(row: .time))
    }

    // MARK: - In the session

    @Test func commandReturnWalksTheCardOnceTheCursorIsOn() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let actionsBefore = model.snapshot.actions.count
        #expect(session.keyCursor == nil)

        // `⌘↩` past `What?` — the view calls this from the editor's `onAdvance`.
        session.advanceKeyCursor()
        #expect(session.keyCursor == CardKeyCursor(row: .context))
        #expect(session.keyHighlight(in: .context) == 0)
        #expect(session.keyHighlight(in: .time) == nil)

        // While the walk runs, `⌘↩` is "next row", never the 2-minute rule.
        #expect(await session.handle(character: "\r", command: true))
        #expect(session.keyCursor?.row == .time)
        #expect(await session.handle(character: "\r", command: true))
        #expect(session.keyCursor?.row == .dates)
        #expect(await session.handle(character: "\r", command: true))
        #expect(session.keyCursor?.row == .outcome)
        #expect(await session.handle(character: "\r", command: true))
        #expect(session.keyCursor?.row == .outcome)
        #expect(model.snapshot.actions.count == actionsBefore, "⌘↩ filed nothing")
    }

    @Test func withoutACursorCommandReturnIsStillDone() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let actionsBefore = model.snapshot.actions.count
        #expect(await session.handle(character: "\r", command: true))
        #expect(model.snapshot.actions.count == actionsBefore + 1)
    }

    @Test func returnTogglesTheHighlightedChip() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let contexts = session.contexts
        #expect(contexts.count >= 2)

        session.moveKeyCursor(by: 1)          // Tab with no walk yet starts it
        #expect(session.keyCursor == CardKeyCursor(row: .context, index: 0))
        session.moveKeyCursor(by: 1)
        #expect(await session.pressKeyCursor())
        #expect(session.draft.contexts == [contexts[1]])
        #expect(await session.pressKeyCursor())
        #expect(session.draft.contexts.isEmpty, "↩ on a selected chip deselects it")

        session.advanceKeyCursor()
        session.moveKeyCursor(by: -1)          // ⇧Tab wraps to the last bucket
        #expect(await session.pressKeyCursor())
        #expect(session.draft.timeBucket == .over60)
        session.moveKeyCursor(by: 1)
        #expect(await session.pressKeyCursor())
        #expect(session.draft.timeBucket == .upTo10, "single-select: the new bucket replaces it")
    }

    @Test func aRefusedOutcomeMovesTheCursorToTheMissingRow() async {
        let (session, model, _) = await InboxTestSupport.openedActionCard()
        let actionsBefore = model.snapshot.actions.count
        session.draft.why = "It has been open for two weeks."
        session.draft.what = "Ring them"
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        #expect(session.keyCursor?.outcome == .next)

        await session.pressKeyCursor()
        #expect(session.refusal?.reason == .missing([.context, .timeEstimate]))
        #expect(session.keyCursor == CardKeyCursor(row: .context), "back to the first missing row")

        await session.pressKeyCursor()                 // selects the first context
        session.advanceKeyCursor()
        await session.pressKeyCursor()                 // and the first time bucket
        session.advanceKeyCursor()
        session.advanceKeyCursor()                     // over the date row
        #expect(session.keyCursor?.outcome == .next)
        await session.pressKeyCursor()
        #expect(model.snapshot.actions.count == actionsBefore + 1)
        #expect(session.keyCursor == nil, "the next card starts without a walk")
        #expect(session.step == .step1)
    }

    @Test func aMissingTextFieldTakesTheCursorAwayAndAsksForFocus() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        session.advanceKeyCursor()
        await session.pressKeyCursor()
        #expect(session.keyCursor == nil)
        #expect(session.focusRequest == .why)
    }

    @Test func projectOpensThePickerAndWaitingItsSheet() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.draft.what = "Ring them"
        await session.perform(.project)
        #expect(session.sheet == .project)
        session.cancelSheet()
        await session.perform(.waiting)
        #expect(session.sheet == .waiting)
    }

    @Test func escapeLeavesTheWalkBeforeItCollapses() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.advanceKeyCursor()
        #expect(session.escape() == .clearedCursor)
        #expect(session.keyCursor == nil)
        #expect(session.step == .actionCard)
        #expect(session.escape() == .collapsed)
    }

    @Test func focusingAFieldEndsTheWalk() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.advanceKeyCursor()
        session.isFieldFocused = true
        #expect(session.keyCursor == nil)
        session.isFieldFocused = false
        session.moveKeyCursor(by: 1)
        #expect(session.keyCursor != nil)
    }

    @Test func theChipWalkStaysOnTheActionCard() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.advanceKeyCursor()
        session.moveKeyCursor(by: 1)
        #expect(session.keyCursor == nil, "step 1 walks its bar, not the chips")
        #expect(session.barHighlight == 1)
    }

    @Test func theLegendShowsTheWalkingKeysWhileWalking() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        let filing = session.legendString
        session.advanceKeyCursor()
        #expect(session.legendString == "Tab ⇧Tab Move · ↩ Select · ⌘↩ Next row · Esc Back")
        session.advanceKeyCursor()                     // time
        session.advanceKeyCursor()                     // dates
        #expect(session.legendString == "Tab ⇧Tab Move · ↩ Choose · ⌘↩ Next row · Esc Back",
                "the date row opens pickers: Choose, not Select")
        session.advanceKeyCursor()
        #expect(session.legendString == "Tab ⇧Tab Move · ↩ Choose · Esc Back")
        _ = session.escape()
        #expect(session.legendString == filing)
    }

    // MARK: - The date row (#77)

    @Test func returnOnTheDateRowOpensTheChipsPicker() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.pointKeyCursor(at: CardKeyCursor(row: .dates, index: 0))
        #expect(await session.pressKeyCursor())
        #expect(session.datePicker == .deferDate)
        session.datePicker = nil
        session.moveKeyCursor(by: 1)
        #expect(await session.pressKeyCursor())
        #expect(session.datePicker == .due)
        session.moveKeyCursor(by: 1)
        #expect(await session.pressKeyCursor())
        #expect(session.sheet == .project, "+ project opens the picker, as a click does")
        #expect(session.draft.deferDate == nil, "opening a picker sets nothing")
    }

    // MARK: - A click moves the highlight (#77)

    @Test func aClickedChipCarriesTheWalkFromThere() async {
        let (session, _, _) = await InboxTestSupport.openedActionCard()
        session.isFieldFocused = true                  // typing in `What?`
        // The view calls this when the mouse clicks `≤30`.
        session.pointKeyCursor(at: CardKeyCursor(row: .time, index: 1))
        #expect(!session.isFieldFocused, "the click takes the keys away from the field")
        #expect(session.keyCursor == CardKeyCursor(row: .time, index: 1))
        session.moveKeyCursor(by: 1)
        #expect(await session.pressKeyCursor())
        #expect(session.draft.timeBucket == .upTo60, "Tab then ↩ go on from the clicked chip")
        session.advanceKeyCursor()
        #expect(session.keyCursor?.row == .dates)
    }

    @Test func aClickedBarButtonTakesTheHighlight() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.pointBar(at: .trash)
        #expect(session.barHighlight == 2)
        await session.take(.openKeep)
        session.pointBar(at: .more)
        #expect(session.barHighlight == session.barStops.count - 1)
    }

    // MARK: - Step 1 (#77)

    @Test func stepOneStartsOnActionAndReturnOpensIt() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        #expect(session.barStops == [.openAction, .openKeep, .trash, .deferToReview])
        #expect(session.barHighlight == 0, "Action is preselected")
        #expect(await session.pressKeyCursor())
        #expect(session.step == .actionCard)
        #expect(session.barHighlight == nil, "the action card has no bar walk")
    }

    @Test func tabWalksStepOneAndWraps() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        session.moveKeyCursor(by: 1)
        #expect(session.barHighlight == 1)
        session.moveKeyCursor(by: 1)
        #expect(session.barHighlight == 2)
        session.moveKeyCursor(by: 1)
        #expect(session.barHighlight == 3)
        session.moveKeyCursor(by: 1)
        #expect(session.barHighlight == 0, "Tab past Defer to review wraps to Action")
        session.moveKeyCursor(by: -1)
        #expect(session.barHighlight == 3, "⇧Tab from Action wraps to Defer to review")
        #expect(await session.pressKeyCursor())
        #expect(session.sheet == .deferToReview)
        session.cancelSheet()

        session.moveKeyCursor(by: -1)                  // Trash
        #expect(await session.pressKeyCursor())
        #expect(model.snapshot.inboxItem(item.id) == nil)
        #expect(session.barHighlight == 0, "the next card starts on Action again")
    }

    @Test func theLetterKeysStillWorkBesideTheWalk() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.moveKeyCursor(by: 2)
        #expect(await session.handle(character: "k"))
        #expect(session.step == .keepCard)
        #expect(session.barHighlight == 0, "a new step starts on its first button")
    }

    @Test func escapeOnStepOneStillQuits() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        session.moveKeyCursor(by: 1)
        #expect(session.escape() == .quit)
    }

    @Test func aCollapsedCardComesBackOnAction() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.openKeep)
        session.moveKeyCursor(by: 1)
        #expect(session.escape() == .collapsed)
        #expect(session.barHighlight == 0)
    }

    // MARK: - The Knowledge / List card (#77)

    @Test func theNavbarWalkStartsOnKnowledgeAndFilesIntoAList() async {
        let (session, model, _) = InboxTestSupport.makeSession()
        let item = try! #require(session.current)
        await session.take(.openKeep)
        let first = try! #require(Rules.favouriteLists(model.snapshot).first)
        #expect(session.barStops.first == .knowledge)
        #expect(session.barStops.last == .more)
        #expect(session.barHighlight == 0)
        #expect(await session.pressKeyCursor())
        #expect(session.sheet == .knowledge)
        session.cancelSheet()

        session.moveKeyCursor(by: -1)
        #expect(await session.pressKeyCursor())
        #expect(session.sheet == .more, "⇧Tab from Knowledge wraps to More…")
        session.cancelSheet()

        session.moveKeyCursor(by: 2)                   // More… → Knowledge → the first list
        #expect(session.barStops[session.barHighlight ?? 0] == .list(first.name))
        #expect(await session.pressKeyCursor())
        #expect(model.snapshot.inboxItem(item.id) == nil)
    }

    @Test func theNotesFieldHidesTheNavbarHighlight() async {
        let (session, _, _) = InboxTestSupport.makeSession()
        await session.take(.openKeep)
        session.isFieldFocused = true
        #expect(session.barHighlight == nil)
        session.moveKeyCursor(by: 1)
        #expect(!(await session.pressKeyCursor()), "keys typed into Notes never press a slot")
        #expect(!session.legendString.contains("Tab"))
        session.isFieldFocused = false                  // `⌘↩` past Notes, or Esc
        #expect(session.barHighlight == 0)
    }
}
