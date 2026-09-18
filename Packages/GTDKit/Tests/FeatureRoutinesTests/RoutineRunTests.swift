import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureRoutines

/// `RoutineRun` end to end, on Linux, against `AppModel` + `InMemoryBackend` and the
/// Morning/Bedtime fixtures — this is the only verification the SwiftUI runner/home views get
/// (they are compiled blind; see `Packages/GTDKit/Sources/FeatureRoutines/README.md`).
@MainActor
struct RoutineRunTests {

    // MARK: - resumeIndex (pure — no AppModel needed)

    @Test func resumeIndexStartsAtZeroWithNoLogForToday() {
        let index = RoutineRun.resumeIndex(
            routine: Fixtures.morningRoutine, log: [], today: Fixtures.today)
        #expect(index == 0)
    }

    @Test func resumeIndexSkipsStepsAlreadyLoggedToday() {
        let routine = Fixtures.morningRoutine
        let log = routine.steps.prefix(3).map { step in
            RoutineLogEntry(
                day: Fixtures.today, routine: routine.title, step: step.id,
                result: .done, at: Date(), device: "iPhone")
        }
        let index = RoutineRun.resumeIndex(routine: routine, log: log, today: Fixtures.today)
        #expect(index == 3)
    }

    @Test func resumeIndexIsPastTheEndWhenEveryStepWasLoggedOnAnEarlierDay() {
        // The fixture log covers days -10…-1, never today (Fixtures.today).
        let index = RoutineRun.resumeIndex(
            routine: Fixtures.morningRoutine, log: Fixtures.routineLog, today: Fixtures.day(-1))
        #expect(index == Fixtures.morningRoutine.steps.count)
    }

    @Test func resumeIndexIgnoresLogEntriesForStepsTheTemplateNoLongerHas() {
        // Mid-day template edit: step "b" was removed/renamed after "a" was logged today.
        let routine = Routine(
            id: NoteID(path: "GTD/Routines/Test.md"), title: "Test",
            steps: [RoutineStep(id: "a", title: "A"), RoutineStep(id: "c", title: "C")])
        let log = [
            RoutineLogEntry(
                day: Fixtures.today, routine: "Test", step: "a", result: .done, at: Date(),
                device: "iPhone"),
            RoutineLogEntry(
                day: Fixtures.today, routine: "Test", step: "b", result: .done, at: Date(),
                device: "iPhone"),
        ]
        let index = RoutineRun.resumeIndex(routine: routine, log: log, today: Fixtures.today)
        #expect(index == 1) // resumes at "c" — "b"'s orphaned entry is simply ignored
    }

    @Test func resumeIndexFindsAStepInsertedMidTemplateEvenPastAlreadyLoggedLaterSteps() {
        // Mid-day template edit: a brand-new step "b2" was inserted between "b" and "c", after
        // "a", "b" and "c" had already been logged under the old template.
        let routine = Routine(
            id: NoteID(path: "GTD/Routines/Test.md"), title: "Test",
            steps: [
                RoutineStep(id: "a", title: "A"), RoutineStep(id: "b", title: "B"),
                RoutineStep(id: "b2", title: "B2"), RoutineStep(id: "c", title: "C"),
            ])
        let log = ["a", "b", "c"].map { id in
            RoutineLogEntry(
                day: Fixtures.today, routine: "Test", step: id, result: .done, at: Date(),
                device: "iPhone")
        }
        let index = RoutineRun.resumeIndex(routine: routine, log: log, today: Fixtures.today)
        #expect(index == 2) // resumes at the new "b2"
    }

    // MARK: - RoutineProgress (home list, R3)

    @Test func progressIsNotStartedWithNoLogToday() {
        let progress = RoutineProgress.today(
            routine: Fixtures.morningRoutine, log: [], today: Fixtures.today)
        #expect(progress == .notStarted)
        #expect(progress.homeText == "Not started")
    }

    @Test func progressIsInProgressPartway() {
        let routine = Fixtures.morningRoutine
        let log = routine.steps.prefix(3).map { step in
            RoutineLogEntry(
                day: Fixtures.today, routine: routine.title, step: step.id,
                result: .done, at: Date(), device: "iPhone")
        }
        let progress = RoutineProgress.today(routine: routine, log: log, today: Fixtures.today)
        #expect(progress == .inProgress(completed: 3, total: routine.steps.count))
        #expect(progress.homeText == "3 of 8")
    }

    @Test func progressIsFinishedWhenEveryStepIsLogged() {
        let progress = RoutineProgress.today(
            routine: Fixtures.morningRoutine, log: Fixtures.routineLog, today: Fixtures.day(-1))
        #expect(progress == .finished)
        #expect(progress.homeText == "Finished")
    }

    // MARK: - Journaling heuristic (R4 — no text input, ever, regardless of this match)

    @Test func journalingStepsAreDetectedFromTheirOwnWords() {
        #expect(Fixtures.morningRoutine.steps.first { $0.title == "Record dreams" }?.isJournaling == true)
        #expect(Fixtures.bedtimeRoutine.steps.first { $0.title == "Reflect on day" }?.isJournaling == true)
        #expect(Fixtures.morningRoutine.steps.first { $0.title == "Cold shower" }?.isJournaling == false)
        #expect(Fixtures.morningRoutine.steps.first { $0.title == "Get things done" }?.isJournaling == false)
    }

    // MARK: - RoutineRun driving AppModel + InMemoryBackend

    private func makeThreeStepRoutine() -> Routine {
        Routine(
            id: NoteID(path: "GTD/Routines/Test.md"), title: "Test",
            time: DayTime(hour: 7, minute: 0),
            steps: [
                RoutineStep(id: "a", title: "A"),
                RoutineStep(id: "b", title: "B", substeps: ["b sub"]),
                RoutineStep(id: "c", title: "C"),
            ])
    }

    private func makeModel(
        routine: Routine, log: [RoutineLogEntry] = [], today: Day = Fixtures.today
    ) -> AppModel {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.routines = [routine]
        snapshot.routineLog = log
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test",
            env: { ReducerEnv(now: Date(), today: today, deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { today })
    }

    @Test func resumesFromScratchAndAdvancesOnLog() async throws {
        let routine = makeThreeStepRoutine()
        let model = makeModel(routine: routine)
        let run = try #require(RoutineRun(model: model, routine: routine.id))

        #expect(run.index == 0)
        #expect(run.currentStep?.id == "a")
        #expect(run.progressText == "Test · 1 of 3")

        let logged = await run.log(.done)

        #expect(logged)
        #expect(run.index == 1)
        #expect(run.currentStep?.id == "b")
        #expect(model.snapshot.routineLog.count == 1)
        #expect(model.snapshot.routineLog.first?.step == "a")
        #expect(model.snapshot.routineLog.first?.result == .done)
    }

    @Test func goingBackAndReLoggingReplacesTheEarlierEntry() async throws {
        let routine = makeThreeStepRoutine()
        let model = makeModel(routine: routine)
        let run = try #require(RoutineRun(model: model, routine: routine.id))

        _ = await run.log(.done) // "a" → done
        run.back()
        #expect(run.index == 0)
        #expect(run.currentStep?.id == "a")
        _ = await run.log(.skipped) // "a" → skipped, replacing the earlier entry (R5)

        let entriesForA = model.snapshot.routineLog.filter { $0.step == "a" }
        #expect(entriesForA.count == 1)
        #expect(entriesForA.first?.result == .skipped)
        #expect(run.index == 1)
    }

    @Test func finishesAfterTheLastStepAndSummarisesDoneAndSkipped() async throws {
        let routine = makeThreeStepRoutine()
        let model = makeModel(routine: routine)
        let run = try #require(RoutineRun(model: model, routine: routine.id))

        _ = await run.log(.done)
        _ = await run.log(.skipped)
        #expect(!run.isFinished)
        _ = await run.log(.done)

        #expect(run.isFinished)
        #expect(run.currentStep == nil)
        #expect(run.doneCount == 2)
        #expect(run.skippedCount == 1)
    }

    @Test func resumesFromWhereAnEarlierSessionLeftOffToday() throws {
        let routine = makeThreeStepRoutine()
        let log = [
            RoutineLogEntry(
                day: Fixtures.today, routine: "Test", step: "a", result: .done, at: Date(),
                device: "iPhone"),
        ]
        let model = makeModel(routine: routine, log: log)
        let run = try #require(RoutineRun(model: model, routine: routine.id))
        #expect(run.index == 1)
        #expect(run.currentStep?.id == "b")
    }

    @Test func aFailedLogLeavesTheStepInPlaceInsteadOfSilentlyAdvancing() async throws {
        let routine = makeThreeStepRoutine()
        var snapshot = Fixtures.sampleSnapshot
        snapshot.routines = [routine]
        let backend = AlwaysFailingBackend(snapshot: snapshot)
        let model = AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
        let run = try #require(RoutineRun(model: model, routine: routine.id))

        let logged = await run.log(.done)

        #expect(logged == false)
        #expect(run.index == 0)
        #expect(run.currentStep?.id == "a")
    }

    @Test func dayRolloverWhileARunIsOpenKeepsAdvancingAndStillCountsEveryStep() async throws {
        let routine = makeThreeStepRoutine()
        let box = DayBox(Fixtures.today)
        var snapshot = Fixtures.sampleSnapshot
        snapshot.routines = [routine]
        let backend = InMemoryBackend(
            snapshot: snapshot, deviceID: "test",
            env: { ReducerEnv(now: Date(), today: box.day, deviceID: "test") })
        let model = AppModel(backend: backend, snapshot: snapshot, today: { box.day })
        let run = try #require(RoutineRun(model: model, routine: routine.id))

        _ = await run.log(.done) // logged under day 1

        box.day = Fixtures.day(1) // midnight passes while the card is still open

        _ = await run.log(.skipped) // logged under day 2
        _ = await run.log(.done) // logged under day 2

        #expect(run.isFinished)
        #expect(run.index == 3)
        // The open run's own summary counts every step it logged, on either side of midnight —
        // even though each entry keeps the day it actually happened on (R5 is untouched).
        #expect(run.doneCount == 2)
        #expect(run.skippedCount == 1)

        let byDay = Dictionary(grouping: model.snapshot.routineLog, by: \.day)
        #expect(byDay[Fixtures.today]?.count == 1)
        #expect(byDay[Fixtures.day(1)]?.count == 2)
    }
}

/// A day that can change mid-test, to simulate midnight passing while a `RoutineRun` stays open.
/// `@unchecked Sendable`: only ever mutated from the (single) test task before being read.
private final class DayBox: @unchecked Sendable {
    var day: Day
    init(_ day: Day) { self.day = day }
}

/// A backend whose every command fails — there is no command to edit a routine's steps
/// (ARCHITECTURE §4 is frozen), so this is how `RoutineRun.log`'s failure path is exercised
/// instead of a live template edit. A plain class (not an actor): every stored property is an
/// immutable `Sendable` value, so `@unchecked Sendable` is sound and sidesteps actor isolation
/// entirely for what is otherwise a trivial stub.
private final class AlwaysFailingBackend: GTDBackend, @unchecked Sendable {
    private let snapshot: VaultSnapshot

    init(snapshot: VaultSnapshot) { self.snapshot = snapshot }

    func snapshots() -> AsyncStream<VaultSnapshot> {
        AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func currentSnapshot() async -> VaultSnapshot { snapshot }
    func perform(_ command: GTDCommand) async throws -> [AppPrompt] {
        throw GTDError.invalid("simulated failure")
    }
    func undo() async throws { throw GTDError.invalid("nothing to undo") }
    func undoLabel() async -> String? { nil }
}
