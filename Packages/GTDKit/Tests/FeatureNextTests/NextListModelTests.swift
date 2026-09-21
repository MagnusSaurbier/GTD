import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
import DesignSystem
@testable import FeatureNext

@MainActor
struct NextListModelTests {

    private func makeModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot,
            deviceID: "test",
            env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    // MARK: - Filtering (E1)

    @Test func fullModeMatchesRulesNextList() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        #expect(list.items.map(\.id) == Rules.nextList(Fixtures.sampleSnapshot, today: Fixtures.today).map(\.id))
        #expect(list.items.prefix(2).allSatisfy { $0.status == .inProgress })
    }

    @Test func settingContextsAndTimeNarrowsTheList() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        list.setContexts(["errands"])
        #expect(!list.items.isEmpty)
        #expect(list.items.allSatisfy { $0.contexts.contains("errands") })
        #expect(list.isFiltered)

        list.setTimeAvailable(10)
        #expect(list.items.allSatisfy { $0.timeEstimate == nil || $0.timeEstimate! <= 10 })

        list.clearFilters()
        #expect(!list.isFiltered)
        #expect(list.contexts.isEmpty)
        #expect(list.timeAvailable == nil)
    }

    @Test func toggleContextAddsAndRemoves() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        list.toggleContext("mac")
        #expect(list.contexts == ["mac"])
        list.toggleContext("phone")
        #expect(list.contexts == ["mac", "phone"])
        list.toggleContext("mac")
        #expect(list.contexts == ["phone"])
    }

    @Test func emptyStateDistinguishesFilteredFromUnfiltered() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        #expect(!list.isEmpty)

        // "Nothing fits 10 min at campus" — the only Next-eligible `campus` action ("Return the
        // library books") is estimated at 30 min, and an undecided estimate is never filtered
        // away (§1 "no lying defaults"), so this has to be a context with no undecided actions
        // at all to actually come up empty.
        list.setContexts(["campus"])
        list.setTimeAvailable(10)
        let campusUnder10 = Rules.nextList(
            Fixtures.sampleSnapshot, contexts: ["campus"], timeAvailable: 10, today: Fixtures.today)
        #expect(campusUnder10.isEmpty, "fixture assumption: the one campus action needs 30 min")
        #expect(list.items.isEmpty)
        // `chase` ignores filters (see `chaseMatchesRulesAndIsUnaffectedByFilters`), so it still
        // has its one item here — `isEmpty`/the empty state itself are about `items` alone when
        // chase is showing something; the wording still needs to reflect the active filter.
        #expect(list.isFiltered)
        #expect(list.emptyStateTitle == Copy.emptyNextFilteredTitle)
        #expect(list.emptyStateBody == Copy.emptyNextFilteredBody)

        list.clearFilters()
        #expect(list.emptyStateTitle == Copy.emptyNextTitle)
        #expect(list.emptyStateBody == Copy.emptyNextBody)
    }

    @Test func isEmptyRequiresBothTheListAndChaseToBeEmpty() {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.actions = snapshot.actions.filter { $0.status.isClosed }
        let list = NextListModel(model: makeModel(snapshot: snapshot), mode: .full, store: InMemoryNextFilterStore())
        #expect(list.items.isEmpty)
        #expect(list.chase.isEmpty)
        #expect(list.isEmpty)
        #expect(list.emptyStateTitle == Copy.emptyNextTitle, "unfiltered — the plain empty state")
    }

    // MARK: - On-the-go (E2)

    @Test func onTheGoNarrowsAvailableContexts() {
        let list = NextListModel(model: makeModel(), mode: .onTheGo, store: InMemoryNextFilterStore())
        #expect(list.availableContexts == Fixtures.sampleSnapshot.config.onTheGoContexts)
    }

    @Test func onTheGoHardFilterCannotBeRemoved() {
        let list = NextListModel(model: makeModel(), mode: .onTheGo, store: InMemoryNextFilterStore())
        let allowed = Set(Fixtures.sampleSnapshot.config.onTheGoContexts)

        // No context selected — "isFiltered" is false — yet the on-the-go set still restricts
        // the list: this is the hard filter, not a user choice.
        #expect(list.contexts.isEmpty)
        #expect(!list.isFiltered)
        #expect(!list.items.isEmpty)
        #expect(list.items.allSatisfy { !Set($0.contexts).isDisjoint(with: allowed) })

        // A context outside the on-the-go set can never be selected through this model's own
        // chips (`availableContexts` only ever offers the allowed ones); if one reached
        // `Rules.onTheGoNextList` regardless it now yields nothing rather than silently
        // falling back to "no filter" (Rules hardening) — the hard restriction never lifts.
        list.setContexts(["mac"])
        #expect(list.items.isEmpty)
    }

    // MARK: - Cap (STYLEGUIDE §2.2)

    @Test func capBelowIsPlainCountAboveIsBadge() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        #expect(list.capCount == Fixtures.sampleSnapshot.config.nextCap - 1)
        #expect(list.capBadge == nil)

        // Promote one Someday item — the sample vault sits at cap − 1, so this exactly fills it.
        let somedayAction = try #require(model.snapshot.actions.first { $0.status == .someday })
        try await model.send(.setStatus(somedayAction.id, .next, waiting: nil))

        #expect(list.capCount == Fixtures.sampleSnapshot.config.nextCap)
        let badge = try #require(list.capBadge)
        #expect(badge.text == "15/15")
        #expect(badge.step == .attention)
    }

    @Test func rowMetaAndSpokenLabelCarryProjectContextsTimeAndBadges() throws {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(list.items.first { $0.project != nil && !$0.contexts.isEmpty })
        let parts = list.metaParts(for: action)
        #expect(parts.first == list.projectTitle(for: action))
        #expect(action.contexts.allSatisfy(parts.contains))

        let spoken = list.spokenLabel(for: action)
        #expect(spoken.hasPrefix(action.title))
        #expect(!spoken.contains("·"), "separators are spoken as pauses, not as 'middle dot'")
        for badge in list.badges(for: action) {
            #expect(spoken.contains(badge.accessibilityLabel))
        }
    }

    @Test func capHeaderIsLabelledAndShowsTheLimit() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        let cap = Fixtures.sampleSnapshot.config.nextCap
        #expect(list.capHeaderText == "Next · \(cap - 1)/\(cap)")
        #expect(list.visibleCountText == nil, "every Next action is visible — nothing to explain")
        #expect(list.capHeaderSpokenText.contains("\(cap - 1) of \(cap) in Next"))

        list.setContexts(["errands"])
        #expect(list.visibleCountText == "\(list.items.count) of \(cap - 1) shown")
        #expect(list.capHeaderText == "Next · \(cap - 1)/\(cap)", "filters never change the cap count")
    }

    @Test func onTheGoHeaderSaysHowManyOfNextAreVisible() {
        let list = NextListModel(model: makeModel(), mode: .onTheGo, store: InMemoryNextFilterStore())
        let cap = Fixtures.sampleSnapshot.config.nextCap
        #expect(list.items.count < list.capCount, "the sample vault has Next actions outside the on-the-go contexts")
        #expect(list.visibleCountText == "\(list.items.count) of \(cap - 1) on the go")
        #expect(list.capHeaderSpokenText.contains("on the go"))
    }

    @Test func capCountIgnoresTheViewsOwnFilters() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        let unfiltered = list.capCount
        list.setContexts(["reading"])
        #expect(list.capCount == unfiltered, "the cap reflects real occupancy, not the filtered row count")
    }

    @Test func capOverTheLimitIsOverdueStyled() {
        // Only reachable via a hand-edited vault (ARCHITECTURE §6) — build the snapshot directly
        // rather than going through the reducer, which refuses to create this state. The sample
        // vault already sits at cap − 1, so two extra actions push it one past the cap.
        var snapshot = Fixtures.sampleSnapshot
        for i in 1...2 {
            snapshot.actions.append(Action(
                id: NoteID(path: "Actions/Extra \(i).md"),
                title: "Extra \(i)", status: .next, created: Fixtures.date(Fixtures.today, 9, 0)))
        }
        let list = NextListModel(model: makeModel(snapshot: snapshot), mode: .full, store: InMemoryNextFilterStore())
        #expect(list.capCount == snapshot.config.nextCap + 1)
        #expect(list.capBadge?.text == "16/15")
        #expect(list.capBadge?.step == .overdue)
    }

    // MARK: - R-2: a deferred Next item comes back into a full list

    /// R-2 — a Next item with a future `defer` is hidden and holds no slot; on its date it is
    /// back in the list and counts again. Nothing is demoted automatically.
    @Test func aDeferredNextItemHoldsNoSlotUntilItsDateReturns() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let before = list.capCount
        let action = try #require(model.snapshot.actions.first { $0.status == .next && $0.deferDate == nil })

        try await list.setDefer(action, to: Fixtures.day(4))
        #expect(list.capCount == before - 1)
        #expect(!list.isOverCap)
        #expect(!list.showsCapSheet)
    }

    /// The flag the view acts on (the sheet itself is T11): armed once per foreground, and only
    /// while Next is actually over the cap.
    @Test func theCapSheetIsOfferedOncePerForegroundUntilSomethingIsDemoted() async throws {
        var snapshot = Fixtures.sampleSnapshot
        for i in 1...2 {
            snapshot.actions.append(Action(
                id: NoteID(path: "Actions/Extra \(i).md"),
                title: "Extra \(i)", status: .next, created: Fixtures.date(Fixtures.today, 9, 0)))
        }
        let model = makeModel(snapshot: snapshot)
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())

        #expect(list.isOverCap)
        #expect(list.showsCapSheet)            // opening the app is the first foreground
        list.capSheetShown()
        #expect(!list.showsCapSheet)           // …and not twice in the same foreground
        list.enteredForeground()
        #expect(list.showsCapSheet)            // still over the cap: due again

        let victim = try #require(list.items.first { $0.status == .next })
        try await list.demoteToSomeday(victim)
        #expect(!list.isOverCap)
        #expect(!list.showsCapSheet)           // repaired: nothing left to ask about
        list.enteredForeground()
        #expect(!list.showsCapSheet)
    }

    /// Below the cap there is nothing to present, whatever the foreground says.
    @Test func theCapSheetIsNeverOfferedBelowTheCap() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        #expect(!list.isOverCap)
        #expect(!list.showsCapSheet)
        list.enteredForeground()
        #expect(!list.showsCapSheet)
    }

    // MARK: - Chase (W2)

    @Test func chaseMatchesRulesAndIsUnaffectedByFilters() {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        #expect(list.chase.map(\.id) == Rules.chaseItems(Fixtures.sampleSnapshot, today: Fixtures.today).map(\.id))
        #expect(list.chase.count == 1)

        list.setContexts(["mac"])
        list.setTimeAvailable(10)
        #expect(list.chase.count == 1, "chasing is not about what fits your current context")
    }

    @Test func bumpFollowUpPushesTheDateOut() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let chaseItem = try #require(list.chase.first)
        let originalFollowUp = try #require(chaseItem.followUpDate)

        try await list.bumpFollowUp(chaseItem, by: 7)

        let updated = try #require(model.snapshot.action(chaseItem.id))
        #expect(updated.followUpDate == originalFollowUp.adding(days: 7))
        #expect(updated.status == .waiting)
    }

    @Test func resolveChaseCompletesTheAction() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let chaseItem = try #require(list.chase.first)

        try await list.resolveChase(chaseItem)

        #expect(model.snapshot.action(chaseItem.id)?.status == .done)
        #expect(list.chase.isEmpty)
    }

    /// STYLEGUIDE §3.3: `Chase: <who> — <what>` with a who on file, `Chase: <what>` — never a
    /// dangling "— " — once W1/D39 lets `who` be empty.
    @Test func chaseTitleNamesWhoWhenPresentAndOmitsTheDashWhenNot() {
        #expect(NextListModel.chaseTitle(who: "Finanzamt", what: "Renew passport") == "Chase: Finanzamt — Renew passport")
        #expect(NextListModel.chaseTitle(who: "", what: "Renew passport") == "Chase: Renew passport")
        #expect(NextListModel.chaseTitle(who: nil, what: "Renew passport") == "Chase: Renew passport")
    }

    @Test func chaseTitleForActionReadsItsWaitingForAndTitle() throws {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        let chaseItem = try #require(list.chase.first)
        #expect(list.chaseTitle(for: chaseItem) == NextListModel.chaseTitle(who: chaseItem.waitingFor, what: chaseItem.title))
    }

    // MARK: - Inline checklist (A2)

    @Test func showsChecklistOnlyWithTwoOrMoreCheckboxes() throws {
        let list = NextListModel(model: makeModel(), mode: .full, store: InMemoryNextFilterStore())
        let withChecklist = try #require(list.items.first { $0.title == "Write DAAD motivation letter" })
        let withoutChecklist = try #require(list.items.first { $0.title == "Order the new passport photo" })
        #expect(list.showsChecklist(withChecklist))
        #expect(!list.showsChecklist(withoutChecklist))
        #expect(!list.allChecked(withChecklist))
    }

    @Test func tickingEveryCheckboxOffersCompletionWithoutCompletingAutomatically() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.title == "Write DAAD motivation letter" })
        #expect(action.checkboxes.count == 2)

        try await list.toggleCheckbox(action, index: 0)
        let midway = try #require(model.snapshot.action(action.id))
        #expect(!list.allChecked(midway))
        #expect(midway.status != .done, "toggling a checkbox never completes the action by itself")

        try await list.toggleCheckbox(midway, index: 1)
        let allDone = try #require(model.snapshot.action(action.id))
        #expect(list.allChecked(allDone))
        #expect(allDone.status != .done, "the row only offers to complete — it never does so automatically")

        // The explicit offer, once taken, does complete it.
        try await list.complete(allDone)
        #expect(model.snapshot.action(action.id)?.status == .done)
    }

    // MARK: - Row actions

    @Test func completeTicksOffImmediately() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(list.items.first)

        try await list.complete(action)

        #expect(model.snapshot.action(action.id)?.status == .done)
        #expect(!list.items.contains { $0.id == action.id })
    }

    @Test func startMovesToInProgressWithoutChangingCapOccupancy() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.status == .next })
        let before = list.capCount

        try await list.start(action)

        #expect(model.snapshot.action(action.id)?.status == .inProgress)
        #expect(list.capCount == before)
    }

    @Test func demoteToSomedayFreesACapSlot() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.status == .next })
        let before = list.capCount

        try await list.demoteToSomeday(action)

        #expect(model.snapshot.action(action.id)?.status == .someday)
        #expect(list.capCount == before - 1)
    }

    @Test func setWaitingRequiresBothHalvesAndUpdatesTheSnapshot() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.status == .next })

        try await list.setWaiting(action, WaitingInfo(who: "Landlord", followUp: Fixtures.day(3)))

        let updated = try #require(model.snapshot.action(action.id))
        #expect(updated.status == .waiting)
        #expect(updated.waitingFor == "Landlord")
        #expect(updated.followUpDate == Fixtures.day(3))
    }

    @Test func setDeferHidesTheActionUntilTheDate() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.status == .next && $0.deferDate == nil })

        try await list.setDefer(action, to: Fixtures.day(5))

        let updated = try #require(model.snapshot.action(action.id))
        #expect(updated.deferDate == Fixtures.day(5))
        // R-2 — a Next item may carry a future defer. Nothing is demoted behind the user's back:
        // the row simply leaves the list until its date, and holds no slot while it is hidden.
        #expect(updated.status == .next)
        #expect(!list.items.contains { $0.id == action.id }, "deferred actions are hidden until the date (D1)")
        #expect(list.capCount == Rules.countsTowardCap(model.snapshot, today: Fixtures.today))
    }

    @Test func setDeferWithoutADateNeedsNoDemotion() async throws {
        let model = makeModel()
        let list = NextListModel(model: model, mode: .full, store: InMemoryNextFilterStore())
        let action = try #require(model.snapshot.actions.first { $0.status == .next })

        try await list.setDefer(action, to: nil)

        let updated = try #require(model.snapshot.action(action.id))
        #expect(updated.deferDate == nil)
        #expect(updated.status == .next, "clearing a defer date never has to touch the status")
    }

    // MARK: - Persistence (E1: "filters persist per device")

    @Test func filtersSurviveARecreatedModelThroughTheSameStore() {
        let store = InMemoryNextFilterStore()
        let first = NextListModel(model: makeModel(), mode: .full, store: store)
        first.setContexts(["mac", "phone"])
        first.setTimeAvailable(30)

        let second = NextListModel(model: makeModel(), mode: .full, store: store)
        #expect(second.contexts == ["mac", "phone"])
        #expect(second.timeAvailable == 30)
    }

    @Test func fullAndOnTheGoFiltersAreStoredSeparately() {
        let store = InMemoryNextFilterStore()
        let full = NextListModel(model: makeModel(), mode: .full, store: store)
        full.setContexts(["mac"])

        let onTheGo = NextListModel(model: makeModel(), mode: .onTheGo, store: store)
        #expect(onTheGo.contexts.isEmpty, "the Mac's full-list filter must not leak into the iPhone's")

        onTheGo.setContexts(["errands"])
        #expect(full.contexts == ["mac"], "and the reverse")
    }

    @Test func clearFiltersAlsoClearsTheStore() {
        let store = InMemoryNextFilterStore()
        let list = NextListModel(model: makeModel(), mode: .full, store: store)
        list.setContexts(["mac"])
        list.setTimeAvailable(60)

        list.clearFilters()

        let reloaded = NextListModel(model: makeModel(), mode: .full, store: store)
        #expect(reloaded.contexts.isEmpty)
        #expect(reloaded.timeAvailable == nil)
    }
}
