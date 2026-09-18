import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDIntents

/// Placeholder so the target builds and `swift test` has something to run.
/// **T30 replaces this with the real suite.**
struct GTDIntentsPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func captureRejectsEmptyText() {
        #expect(throws: CaptureError.emptyText) { _ = try CaptureRequest(text: "   \n ").normalized() }
        #expect((try? CaptureRequest(text: "  buy milk  ").normalized()) == "buy milk")
    }

    @Test func stampFormat() {
        #expect(CaptureStamp.string(for: Fixtures.date(Fixtures.today, 8, 12, 4),
                                    calendar: Fixtures.calendar) == "2026-09-19 081204")
    }
}
