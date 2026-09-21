import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureProjects

/// Placeholder so the target builds and `swift test` has something to run.
/// **T22 replaces this with the real suite.**
struct FeatureProjectsPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

}
