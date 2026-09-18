import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureOverview

/// Sidebar contents (E3) and the selection routing of the Mac shell.
@MainActor
struct SidebarRoutingTests {

    @Test func everySectionHasATitleAndASymbol() {
        #expect(SidebarItem.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    /// STYLEGUIDE §4.1: Inbox · Next · Backlog · Waiting · Maybe · Projects · Deferred,
    /// then Review and Routines.
    @Test func countedSectionsAreTheSevenOfTheStyleGuide() {
        #expect(SidebarItem.counted == [.inbox, .next, .backlog, .waiting, .maybe, .projects, .deferred])
        #expect(SidebarItem.flows == [.review, .routines])
        #expect(Set(SidebarItem.counted).union(SidebarItem.flows) == Set(SidebarItem.allCases))
    }

    /// `⌘1…⌘7` (STYLEGUIDE §4.5) — and the mapping round-trips.
    @Test func shortcutNumbersCoverTheCountedSections() {
        #expect(SidebarItem.counted.compactMap(\.shortcutNumber) == Array(1...7))
        #expect(SidebarItem.review.shortcutNumber == nil)
        #expect(SidebarItem.routines.shortcutNumber == nil)
        for number in 1...7 {
            #expect(SidebarItem(shortcutNumber: number)?.shortcutNumber == number)
        }
        #expect(SidebarItem(shortcutNumber: 0) == nil)
        #expect(SidebarItem(shortcutNumber: 8) == nil)
    }

    @Test func everyCountedSectionReadsItsCountAndTheOthersDoNot() {
        let counts = Rules.sidebarCounts(Fixtures.sampleSnapshot, today: Fixtures.today)
        for item in SidebarItem.counted {
            #expect(item.count(counts) != nil)
        }
        #expect(SidebarItem.review.count(counts) == nil)
        #expect(SidebarItem.routines.count(counts) == nil)
        #expect(SidebarItem.next.count(counts) == counts.next)
    }

    @Test func onlyBacklogAndMaybeUseTheGenericList() {
        #expect(SidebarItem.backlog.listedStatus == .backlog)
        #expect(SidebarItem.maybe.listedStatus == .maybe)
        #expect(SidebarItem.next.listedStatus == nil)
        #expect(SidebarItem.projects.listedStatus == nil)
    }

    /// D3 — the calendar strip is docked under the lists, not under the guided flows.
    @Test func calendarStripIsHiddenForTheGuidedFlows() {
        #expect(SidebarItem.review.showsCalendarStrip == false)
        #expect(SidebarItem.routines.showsCalendarStrip == false)
        #expect(SidebarItem.next.showsCalendarStrip)
    }

    // MARK: - Navigation

    @Test func shortcutSelectsTheSection() {
        let nav = OverviewNavigation()
        #expect(nav.select(shortcutNumber: 1))
        #expect(nav.selection == .inbox)
        #expect(nav.select(shortcutNumber: 9) == false)
        #expect(nav.selection == .inbox)
    }

    /// Switching section clears the detail column and the ⌘F filter — the filter belongs to
    /// the list it was typed in.
    @Test func changingSectionResetsDetailAndFilter() {
        let nav = OverviewNavigation()
        nav.open(action: NoteID(path: "Actions/Fix the bike light.md"))
        nav.query = "bike"
        nav.isSearching = true

        nav.selection = .backlog

        #expect(nav.detail == nil)
        #expect(nav.query.isEmpty)
        #expect(nav.isSearching == false)
    }

    @Test func selectingTheSameSectionKeepsTheDetailColumn() {
        let nav = OverviewNavigation(selection: .backlog)
        let id = NoteID(path: "Actions/Fix the bike light.md")
        nav.open(action: id)
        nav.selection = .backlog
        #expect(nav.detail == .action(id))
    }

    /// A rename moves the note's file, so the detail column has to follow the new `NoteID`.
    @Test func detailFollowsARename() {
        let nav = OverviewNavigation()
        let old = NoteID(path: "Actions/Fix the bike light.md")
        let new = NoteID(path: "Actions/Fix the bike lamp.md")
        nav.open(action: old)
        nav.replace(old, with: new)
        #expect(nav.detail == .action(new))

        nav.open(project: old)
        nav.replace(old, with: new)
        #expect(nav.detail == .project(new))
    }

    @Test func pruningDropsANoteThatLeftTheVault() {
        let nav = OverviewNavigation()
        let snapshot = Fixtures.sampleSnapshot
        let existing = snapshot.actions[0].id
        nav.open(action: existing)
        nav.prune(against: snapshot)
        #expect(nav.detail == .action(existing))

        nav.open(action: NoteID(path: "Actions/Never existed.md"))
        nav.prune(against: snapshot)
        #expect(nav.detail == nil)
    }
}
