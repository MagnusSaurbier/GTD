import Testing
import Foundation
import GTDModel
import GTDFixtures

struct RulesTests {
    private var snapshot: VaultSnapshot { Fixtures.sampleSnapshot }
    private var today: Day { Fixtures.today }

    @Test func inboxQueueIsLIFOAndExcludesReviewDeferrals() {
        let queue = Rules.inboxQueue(snapshot)
        #expect(queue.allSatisfy { $0.reviewReason == nil })
        #expect(queue == queue.sorted { $0.created > $1.created })
        #expect(Rules.reviewDeferredInbox(snapshot).count == 1)
    }

    @Test func nextListPinsInProgressAndRespectsFilters() {
        let all = Rules.nextList(snapshot, today: today)
        #expect(all.count == snapshot.config.nextCap - 1)
        #expect(all.prefix(2).allSatisfy { $0.status == .inProgress })

        let errands = Rules.nextList(snapshot, contexts: ["errands"], today: today)
        #expect(!errands.isEmpty)
        #expect(errands.allSatisfy { $0.contexts.contains("errands") })

        // An undecided estimate is never filtered away (§1 "no lying defaults").
        let quick = Rules.nextList(snapshot, timeAvailable: 10, today: today)
        #expect(quick.allSatisfy { $0.timeEstimate == nil || $0.timeEstimate! <= 10 })
    }

    @Test func onTheGoListOnlyShowsOnTheGoContexts() {
        let allowed = Set(snapshot.config.onTheGoContexts)
        let list = Rules.onTheGoNextList(snapshot, today: today)
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { !Set($0.contexts).isDisjoint(with: allowed) })
    }

    @Test func chaseAndWaiting() {
        let chase = Rules.chaseItems(snapshot, today: today)
        #expect(chase.count == 1)
        #expect(chase.first?.waitingFor == "Prof. Weber")
        #expect(Rules.waitingList(snapshot, today: today).count == 3)
    }

    @Test func stalledProjects() {
        let stalled = Rules.stalledProjects(snapshot, today: today)
        #expect(stalled.map(\.id) == [Fixtures.flatProject.id])
    }

    @Test func deferredItemsAreHidden() {
        let deferred = Rules.deferredList(snapshot, today: today)
        #expect(deferred.count == 2)
        let visible = Rules.visibleActions(snapshot, today: today).map(\.id)
        #expect(deferred.allSatisfy { !visible.contains($0.id) })
    }

    @Test func sidebarCounts() {
        let counts = Rules.sidebarCounts(snapshot, today: today)
        #expect(counts.inbox == 5)
        #expect(counts.next == 14)
        #expect(counts.waiting == 3)
        #expect(counts.deferred == 2)
        #expect(counts.projects == 4)
    }

    @Test func capSignalOnlyAppearsAtTheCap() {
        #expect(Rules.capSignal(snapshot) == nil)
        var full = snapshot
        full.config.nextCap = 14
        #expect(Rules.capSignal(full)?.step == .attention)
        full.config.nextCap = 13
        #expect(Rules.capSignal(full)?.step == .overdue)
    }

    @Test func signalsFollowTheStyleGuideTable() throws {
        let overdue = try #require(snapshot.actions.first { $0.title == "Reply to the DAAD info mail" })
        #expect(Rules.signals(for: overdue, today: today).contains {
            $0.kind == .overdue(days: 2) && $0.step == .overdue
        })

        let dueSoon = try #require(snapshot.actions.first { $0.title == "Answer Lena about the WG viewing" })
        #expect(Rules.dueBadge(for: dueSoon, today: today)?.step == .aging)

        let chase = try #require(Rules.chaseItems(snapshot, today: today).first)
        #expect(Rules.signals(for: chase, today: today).contains {
            $0.kind == .chase(days: 9) && $0.step == .attention
        })

        let stale = try #require(snapshot.actions.first { $0.title == "Cancel the gym membership" })
        #expect(Rules.signals(for: stale, today: today).contains {
            $0.kind == .untouched(days: 35) && $0.step == .attention
        })

        let oldCapture = try #require(snapshot.inbox.last)
        #expect(Rules.signals(for: oldCapture, today: today).first?.step == .aging)
    }

    @Test func suggestsProjectAtTwoCheckboxes() throws {
        let multi = try #require(snapshot.actions.first { $0.checkboxes.count >= 2 })
        #expect(Rules.suggestsProject(multi))
        let single = try #require(snapshot.actions.first { $0.checkboxes.isEmpty })
        #expect(!Rules.suggestsProject(single))
    }

    @Test func timelineCoversDeferDueAndFollowUp() {
        let entries = Rules.timeline(snapshot, from: today, to: today.adding(days: 13))
        #expect(entries.contains { $0.kind == .due })
        #expect(entries.contains { $0.kind == .followUp })
        #expect(entries.contains { $0.kind == .deferred })
        #expect(entries == entries.sorted { ($0.day, $0.title) < ($1.day, $1.title) })
    }
}
