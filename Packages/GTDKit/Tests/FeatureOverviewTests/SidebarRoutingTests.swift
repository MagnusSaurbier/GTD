import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureOverview

/// Sidebar contents (E3) and the selection routing of the Mac shell.
@MainActor
struct SidebarRoutingTests {

    @Test func everySectionHasATitleAndASymbol() {
        #expect(SidebarItem.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    /// STYLEGUIDE §4.1: Inbox · Next · Someday · Waiting · Lists · Projects · Deferred, then
    /// Review and Routines.
    @Test func countedSectionsAreTheOnesOfTheStyleGuide() {
        #expect(SidebarItem.counted == [
            .inbox, .next, .someday, .waiting, .lists, .projects, .deferred,
        ])
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

    /// A3 merged the two old "not now" tiers, so Someday is the only generic status list left.
    @Test func onlySomedayUsesTheGenericList() {
        #expect(SidebarItem.someday.listedStatus == .someday)
        #expect(SidebarItem.allCases.filter { $0.listedStatus != nil } == [.someday])
        #expect(SidebarItem.next.listedStatus == nil)
        #expect(SidebarItem.projects.listedStatus == nil)
    }

    /// D3 / M4 — the calendar strip is docked only under the lists whose items carry dates.
    @Test func calendarStripIsDockedOnlyUnderTheDatedLists() {
        let docked = SidebarItem.allCases.filter(\.showsCalendarStrip)
        #expect(Set(docked) == [.next, .waiting, .deferred])
    }

    /// M3 — the guided flows span content + detail; every other section keeps the list/detail pair.
    @Test func onlyTheGuidedFlowsSpanTheDetailColumn() {
        #expect(SidebarItem.allCases.filter(\.spansDetailColumn) == SidebarItem.flows)
    }

    /// M8 — the empty detail column names what the section's list holds, and the sections
    /// without a detail column have no such copy at all.
    @Test func emptyDetailCopyFitsTheSection() {
        #expect(SidebarItem.next.emptyDetailBody == OverviewMacCopy.pickAnAction)
        #expect(SidebarItem.projects.emptyDetailBody == OverviewMacCopy.pickAProject)
        #expect(SidebarItem.projects.emptyDetailBody != SidebarItem.next.emptyDetailBody)
        #expect(SidebarItem.inbox.emptyDetailBody != SidebarItem.next.emptyDetailBody)
        for item in SidebarItem.allCases {
            #expect((item.emptyDetailBody == nil) == item.spansDetailColumn)
        }
    }

    /// M1 — the window can never be narrower than its three columns at their minimum.
    @Test func windowFitsTheThreeColumnsAtTheirMinimum() {
        let columns = OverviewLayout.sidebarMinWidth
            + OverviewLayout.listMinWidth + OverviewLayout.detailMinWidth
        #expect(OverviewLayout.windowMinWidth >= columns)
        #expect(OverviewLayout.listIdealWidth >= OverviewLayout.listMinWidth)
        #expect(OverviewLayout.detailIdealWidth >= OverviewLayout.detailMinWidth)
        #expect(OverviewLayout.sidebarIdealWidth >= OverviewLayout.sidebarMinWidth)
    }

    /// M4 — strip day labels are one short word: "tomorrow" wrapped letter by letter.
    @Test func stripDayLabelsAreShortAndSingleWord() {
        let today = Fixtures.today
        #expect(OverviewMacCopy.stripDayLabel(today, today: today) == "today")
        #expect(OverviewMacCopy.stripDayLabel(today.adding(days: 1), today: today) == "Tmrw")
        for offset in 0..<14 {
            let label = OverviewMacCopy.stripDayLabel(today.adding(days: offset), today: today)
            #expect(label.count <= 6, "\(label)")
        }
    }

    /// M2 — the list column highlights the action the detail column shows, nothing else.
    @Test func openActionFollowsTheDetailColumn() {
        let nav = OverviewNavigation()
        #expect(nav.openAction == nil)
        let id = Fixtures.sampleSnapshot.actions[0].id
        nav.open(action: id)
        #expect(nav.openAction == id)
        nav.open(project: Fixtures.sampleSnapshot.projects[0].id)
        #expect(nav.openAction == nil)
    }

    /// M2 — same for the Projects list: it highlights the project the detail column shows, and
    /// an action in that column (opened from a project row) highlights no project.
    @Test func openProjectFollowsTheDetailColumn() {
        let nav = OverviewNavigation()
        #expect(nav.openProject == nil)
        let project = Fixtures.sampleSnapshot.projects[0].id
        nav.open(project: project)
        #expect(nav.openProject == project)
        #expect(nav.openAction == nil)
        nav.open(action: Fixtures.sampleSnapshot.actions[0].id)
        #expect(nav.openProject == nil)
    }

    /// T10 — the single `Lists` row: counted, no calendar strip, has a detail column and reads
    /// `SidebarCounts.lists` (open items across every list, not any one list's count).
    @Test func listsIsACountedSectionWithNoCalendarStripAndItsOwnCount() {
        #expect(SidebarItem.counted.contains(.lists))
        #expect(SidebarItem.lists.showsCalendarStrip == false)
        #expect(SidebarItem.lists.spansDetailColumn == false)
        #expect(SidebarItem.lists.listedStatus == nil)
        #expect(SidebarItem.lists.emptyDetailBody != nil)

        let counts = Rules.sidebarCounts(Fixtures.sampleSnapshot, today: Fixtures.today)
        #expect(SidebarItem.lists.count(counts) == counts.lists)
        #expect(counts.lists == Rules.openListItemCount(Fixtures.sampleSnapshot))
    }

    /// The Deferred section is named "Deferred" in the sidebar; `FeatureWaiting.DeferredView`
    /// titles its screen with the same word rather than with `Copy.deferLabel` ("Defer"), the
    /// date chip's field label (walkthrough 2026-09-19).
    @Test func deferredSectionIsCalledDeferred() {
        #expect(SidebarItem.deferred.title == "Deferred")
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

        nav.selection = .someday

        #expect(nav.detail == nil)
        #expect(nav.query.isEmpty)
        #expect(nav.isSearching == false)
    }

    @Test func selectingTheSameSectionKeepsTheDetailColumn() {
        let nav = OverviewNavigation(selection: .someday)
        let id = NoteID(path: "Actions/Fix the bike light.md")
        nav.open(action: id)
        nav.selection = .someday
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

        nav.open(listItem: old)
        nav.replace(old, with: new)
        #expect(nav.detail == .listItem(new))
    }

    /// T10 — the list column highlights the item the detail column shows, nothing else, exactly
    /// as `openAction`/`openProject` already do.
    @Test func openListItemFollowsTheDetailColumn() {
        let nav = OverviewNavigation()
        #expect(nav.openListItem == nil)
        let item = Fixtures.sampleSnapshot.listItems[0].id
        nav.open(listItem: item)
        #expect(nav.openListItem == item)
        nav.open(action: Fixtures.sampleSnapshot.actions[0].id)
        #expect(nav.openListItem == nil)
    }

    /// A renamed list item's old id is as absent from the snapshot as a deleted one's — `apply`
    /// must follow the rename, not prune it (same rule `applyingAnUpdateKeepsTheDetailOfARenamedNote`
    /// proves for an action).
    @Test func applyingAnUpdateKeepsTheDetailOfARenamedListItem() {
        let nav = OverviewNavigation()
        let snapshot = Fixtures.sampleSnapshot
        let old = NoteID(path: "Lists/Read/Gone by any other name.md")
        let new = snapshot.listItems[0].id
        nav.open(listItem: old)

        nav.apply(snapshot: snapshot, renames: RenameMap(from: old, to: new))

        #expect(nav.detail == .listItem(new))
    }

    @Test func applyingAnUpdateDropsANoteThatLeftTheVault() {
        let nav = OverviewNavigation()
        let snapshot = Fixtures.sampleSnapshot
        let existing = snapshot.actions[0].id
        nav.open(action: existing)
        nav.apply(snapshot: snapshot)
        #expect(nav.detail == .action(existing))

        nav.open(action: NoteID(path: "Actions/Never existed.md"))
        nav.apply(snapshot: snapshot)
        #expect(nav.detail == nil)
    }

    /// The reason `apply` takes the renames: a renamed note's old id is as absent from the
    /// snapshot as a deleted one's, so pruning alone would clear the detail column of the very
    /// action whose title was just edited.
    @Test func applyingAnUpdateKeepsTheDetailOfARenamedNote() throws {
        let nav = OverviewNavigation()
        let snapshot = Fixtures.sampleSnapshot
        let old = NoteID(path: "Actions/Gone by any other name.md")
        let new = snapshot.actions[0].id
        nav.open(action: old)

        nav.apply(snapshot: snapshot, renames: RenameMap(from: old, to: new))

        #expect(nav.detail == .action(new))
    }

    /// E3 — which sections take a dropped row, and what they ask `MovePlan` for. The inbox
    /// (forced order, I1), Lists (an action is not a list item) and the two flows take nothing.
    @Test func everySectionKnowsWhetherARowCanBeDroppedOnIt() {
        #expect(SidebarItem.next.moveDestination == .next)
        #expect(SidebarItem.someday.moveDestination == .someday)
        #expect(SidebarItem.waiting.moveDestination == .waiting)
        #expect(SidebarItem.deferred.moveDestination == .deferred)
        #expect(SidebarItem.projects.moveDestination == .projects)
        for item in [SidebarItem.inbox, .lists, .review, .routines] {
            #expect(item.moveDestination == nil, "\(item)")
        }
    }
}
