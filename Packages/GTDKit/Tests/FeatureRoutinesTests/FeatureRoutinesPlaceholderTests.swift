import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureRoutines

/// Placeholder so the target builds and `swift test` has something to run.
/// **T24 replaces this with the real suite.**
struct FeatureRoutinesPlaceholderTests {
    @Test func fixturesAreAvailable() {
        #expect(!Fixtures.sampleSnapshot.actions.isEmpty)
    }

    @Test func resumeIndexSkipsLoggedSteps() {
        let routine = Fixtures.morningRoutine
        let today = Fixtures.day(-1)
        let index = RoutineRun.resumeIndex(routine: routine, log: Fixtures.routineLog, today: today)
        #expect(index == routine.steps.count)
        #expect(RoutineRun.resumeIndex(routine: routine, log: [], today: Fixtures.today) == 0)
    }
}
