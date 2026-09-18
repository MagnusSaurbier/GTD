import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDServices

/// Placeholder so the target builds and `swift test` has something to run.
/// **T16 replaces this with the real suite.**
struct GTDServicesPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func diffIsNotImplementedYet() {
        #expect(throws: ServiceError.self) {
            _ = try SnapshotDiff.ops(from: .empty, to: .empty, extraOps: [])
        }
    }
}
