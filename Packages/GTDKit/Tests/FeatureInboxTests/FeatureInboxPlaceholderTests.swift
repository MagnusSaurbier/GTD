import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureInbox

/// Placeholder so the target builds and `swift test` has something to run.
/// **T20 replaces this with the real suite.**
struct FeatureInboxPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func dragResolverHonoursAxisLockAndThresholds() {
        let size = CGSize(width: 360, height: 600)
        #expect(DragResolver.target(dx: 8, dy: 4, cardSize: size) == nil)
        #expect(DragResolver.target(dx: 200, dy: 10, cardSize: size) == .next)
        #expect(DragResolver.target(dx: -200, dy: 10, cardSize: size) == .backlog)
        #expect(DragResolver.target(dx: 10, dy: -200, cardSize: size) == .maybe)
        // Trash needs 40 % of the height, so 25 % is not enough.
        #expect(DragResolver.target(dx: 10, dy: 160, cardSize: size) == nil)
        #expect(DragResolver.target(dx: 10, dy: 260, cardSize: size) == .trash)
    }

    @Test func everyTargetHasAKey() {
        #expect(CardTarget.allCases.allSatisfy { !$0.key.isEmpty })
        #expect(CardTarget.allCases.count { $0.isDirect } == 4)
    }
}
