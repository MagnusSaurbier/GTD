import Foundation
import Observation
import GTDModel
import GTDAppCore

/// One run of one routine (R2–R5): steps from the template, today's log decides where to resume.
/// Plain and unit-testable — **no SwiftUI**. Owned by T24.
@MainActor
@Observable
public final class RoutineRun {
    public let routine: Routine
    public private(set) var index: Int

    private let model: AppModel

    public init?(model: AppModel, routine id: NoteID) {
        guard let routine = model.snapshot.routine(id) else { return nil }
        self.model = model
        self.routine = routine
        self.index = 0
        self.index = RoutineRun.resumeIndex(routine: routine, log: model.snapshot.routineLog, today: model.today())
    }

    public var currentStep: RoutineStep? {
        routine.steps.indices.contains(index) ? routine.steps[index] : nil
    }

    public var isFinished: Bool { index >= routine.steps.count }

    /// `Morning · 4 of 11` (STYLEGUIDE §3.7).
    public var progressText: String { "\(routine.title) · \(index + 1) of \(routine.steps.count)" }

    public var doneCount: Int { results(today: model.today()).values.count { $0 == .done } }
    public var skippedCount: Int { results(today: model.today()).values.count { $0 == .skipped } }

    /// Logs the current step and advances. Going back and re-logging replaces the entry (R5).
    public func log(_ result: RoutineStepResult) async {
        guard let step = currentStep else { return }
        try? await model.send(.logRoutineStep(routine: routine.id, stepID: step.id, result))
        index += 1
    }

    /// Horizontal swipe back = previous step (no swipe filing on routine cards).
    public func back() { index = max(index - 1, 0) }

    /// Today's results for this routine, across devices.
    public func results(today: Day) -> [String: RoutineStepResult] {
        var out: [String: RoutineStepResult] = [:]
        for entry in model.snapshot.routineLog
        where entry.day == today && entry.routine == routine.title {
            out[entry.step] = entry.result
        }
        return out
    }

    /// The first step that has no entry for today; the end when everything is logged.
    nonisolated public static func resumeIndex(routine: Routine, log: [RoutineLogEntry], today: Day) -> Int {
        let logged = Set(
            log.filter { $0.day == today && $0.routine == routine.title }.map(\.step))
        return routine.steps.firstIndex { !logged.contains($0.id) } ?? routine.steps.count
    }
}
