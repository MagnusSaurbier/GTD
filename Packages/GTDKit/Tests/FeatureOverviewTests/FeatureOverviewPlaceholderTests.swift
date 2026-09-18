import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureOverview

/// Placeholder so the target builds and `swift test` has something to run.
/// **T25 replaces this with the real suite.**
struct FeatureOverviewPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func sidebarItemsHaveTitlesAndSymbols() {
        #expect(SidebarItem.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        #expect(SidebarItem.allCases.compactMap(\.shortcutNumber) == Array(1...7))
    }
}
