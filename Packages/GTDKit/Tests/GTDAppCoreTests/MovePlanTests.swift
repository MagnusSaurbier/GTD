import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDAppCore

/// Dragging a row onto a sidebar section (or choosing `Move to…`): what has to happen before
/// the item sits in its new category. The reducer keeps the last word on fields and the cap;
/// this pins when a dialogue is needed at all.
struct MovePlanTests {

    private let snapshot = VaultSnapshot.empty
    private let today = Day(year: 2026, month: 9, day: 24)
    private let project = NoteID(path: "Projects/no_area/Umzug.md")
    private let otherProject = NoteID(path: "Projects/no_area/Steuer.md")

    private func action(
        _ status: ActionStatus,
        why: String = "", what: String = "", contexts: [String] = [], time: Int? = nil,
        deferDate: Day? = nil, project: NoteID? = nil
    ) -> Action {
        Action(
            id: NoteID(path: "Actions/Test.md"), title: "Test", status: status,
            contexts: contexts, timeEstimate: time, project: project, deferDate: deferDate,
            why: why, what: what)
    }

    private func plan(_ action: Action, _ destination: MoveDestination) -> MovePlan {
        MovePlan.plan(action: action, to: destination, snapshot: snapshot, today: today)
    }

    // MARK: Tiers

    @Test func aCompleteSomedayItemMovesToNextAtOnce() {
        let item = action(.someday, why: "w", what: "x", contexts: ["mac"], time: 10)
        #expect(plan(item, .next) == .perform(.setStatus(item.id, .next, waiting: nil)))
    }

    /// R-3 — a promotion into Next needs Why, What, a context and a time; the card opens with
    /// exactly those marked, in `RequiredField` order.
    @Test func anIncompleteSomedayItemOpensTheCardForNext() {
        let item = action(.someday, what: "x")
        #expect(plan(item, .next) == .card(status: .next, missing: [.why, .context, .timeEstimate]))
    }

    /// Demoting is never blocked, whatever the note carries (`RequiredField.missing`).
    @Test func demotingToSomedayNeedsNothing() {
        let item = action(.next)
        #expect(plan(item, .someday) == .perform(.setStatus(item.id, .someday, waiting: nil)))
    }

    /// W1/D39 — Waiting always asks for the follow-up date, even from a complete Next item.
    @Test func waitingAlwaysOpensTheCardForItsDate() {
        let item = action(.next, why: "w", what: "x", contexts: ["mac"], time: 10)
        #expect(plan(item, .waiting) == .card(status: .waiting, missing: [.followUpDate]))
    }

    @Test func droppingOnTheOwnSectionDoesNothing() {
        #expect(plan(action(.next), .next) == .alreadyThere)
        #expect(plan(action(.inProgress), .next) == .alreadyThere)
        #expect(plan(action(.someday), .someday) == .alreadyThere)
        #expect(plan(action(.waiting), .waiting) == .alreadyThere)
        #expect(!MovePlan.accepts(action: action(.next), destination: .next, snapshot: snapshot, today: today))
        #expect(MovePlan.accepts(action: action(.next), destination: .someday, snapshot: snapshot, today: today))
    }

    // MARK: Deferred

    @Test func deferredAsksForADate() {
        #expect(plan(action(.next), .deferred) == .deferDate)
        // A defer date that has already arrived is not "deferred" (D1): ask again.
        #expect(plan(action(.next, deferDate: today), .deferred) == .deferDate)
    }

    @Test func anAlreadyDeferredItemStaysWhereItIs() {
        let later = Day(year: 2026, month: 10, day: 1)
        #expect(plan(action(.next, deferDate: later), .deferred) == .alreadyThere)
    }

    // MARK: Projects

    @Test func theProjectsSectionAsksWhichProject() {
        #expect(plan(action(.next), .projects) == .pickProject)
    }

    /// One project per action: dropping on a project replaces the one it named before.
    @Test func aProjectRowAttachesAndReplaces() {
        let item = action(.someday, project: otherProject)
        guard case let .perform(.updateAction(updated)) = plan(item, .project(project)) else {
            Issue.record("expected an updateAction")
            return
        }
        #expect(updated.project == project)
        #expect(updated.id == item.id)
        #expect(updated.status == .someday)
    }

    // MARK: Lists

    @Test func theListsSectionAsksWhichList() {
        #expect(plan(action(.next), .lists) == .pickList)
    }

    @Test func aListMovesTheActionIntoIt() {
        let item = action(.someday)
        #expect(plan(item, .list("Read")) == .perform(.moveActionToList(item.id, list: "Read")))
    }

    @Test func droppingOnTheOwnProjectDoesNothing() {
        #expect(plan(action(.next, project: project), .project(project)) == .alreadyThere)
    }

    // MARK: In progress board (#87)

    /// "Begin action" on a Next item starts it at once: it already holds its slot and fields.
    @Test func aNextItemBeginsAtOnce() {
        let item = action(.next)
        #expect(plan(item, .inProgress) == .perform(.setStatus(item.id, .inProgress, waiting: nil)))
    }

    /// From outside Next, beginning enters Next's tier: the card asks what Next asks.
    @Test func anIncompleteSomedayItemOpensTheCardForInProgress() {
        let item = action(.someday, what: "x")
        #expect(plan(item, .inProgress)
            == .card(status: .inProgress, missing: [.why, .context, .timeEstimate]))
    }

    /// Agent and Review hold no cap slot and ask for nothing — handing over is never blocked.
    @Test func agentAndReviewNeedNothing() {
        let item = action(.someday)
        #expect(plan(item, .agent) == .perform(.setStatus(item.id, .agent, waiting: nil)))
        #expect(plan(item, .review) == .perform(.setStatus(item.id, .review, waiting: nil)))
        let started = action(.inProgress)
        #expect(plan(started, .review) == .perform(.setStatus(started.id, .review, waiting: nil)))
    }

    /// Back from Review to In progress re-enters Next: the same question as any promotion.
    @Test func reviewBackToInProgressAsksWhatNextAsks() {
        let item = action(.review, why: "w", what: "x", contexts: ["mac"], time: 10)
        #expect(plan(item, .inProgress) == .perform(.setStatus(item.id, .inProgress, waiting: nil)))
        #expect(plan(action(.review), .inProgress)
            == .card(status: .inProgress, missing: [.why, .what, .context, .timeEstimate]))
    }

    @Test func droppingOnTheOwnColumnDoesNothing() {
        #expect(plan(action(.inProgress), .inProgress) == .alreadyThere)
        #expect(plan(action(.agent), .agent) == .alreadyThere)
        #expect(plan(action(.review), .review) == .alreadyThere)
    }

    /// An agent's card dropped on Next is a promotion (Agent holds no slot), not "already there".
    @Test func anAgentItemDroppedOnNextIsPromoted() {
        let item = action(.agent, why: "w", what: "x", contexts: ["mac"], time: 10)
        #expect(plan(item, .next) == .perform(.setStatus(item.id, .next, waiting: nil)))
    }
}
