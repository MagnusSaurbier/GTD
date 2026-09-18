import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureWaiting

/// Placeholder so the target builds and `swift test` has something to run.
/// **T23 replaces this with the real suite.**
struct FeatureWaitingPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

}
