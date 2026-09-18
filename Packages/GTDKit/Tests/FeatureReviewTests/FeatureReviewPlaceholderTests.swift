import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureReview

/// Placeholder so the target builds and `swift test` has something to run.
/// **T27 replaces this with the real suite.**
struct FeatureReviewPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func wizardStateRoundTrips() throws {
        let state = ReviewSessionState(year: 2026, week: 38, startedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(ReviewSessionState.self, from: data) == state)
        #expect(ReviewStage.allCases.first == .sweep)
    }
}
