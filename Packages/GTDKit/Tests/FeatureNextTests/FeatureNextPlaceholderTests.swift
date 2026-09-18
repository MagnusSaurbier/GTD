import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureNext

/// Placeholder so the target builds and `swift test` has something to run.
/// **T21 replaces this with the real suite.**
struct FeatureNextPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func modesExist() {
        #expect(NextViewMode.allCases.count == 2)
    }
}
