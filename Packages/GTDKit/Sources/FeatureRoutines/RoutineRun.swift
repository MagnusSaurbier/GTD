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
    /// Every calendar day this open session has written a log entry under. Usually one day; two
    /// if the run stays open across midnight (each entry still keeps its own day — R5's one
    /// file per day is untouched — this only widens what *this* session reads back for its own
    /// summary, so a run that starts at 23:58 still reports every step it logged).
    private var sessionDays: Set<Day>

    public init?(model: AppModel, routine id: NoteID) {
        guard let routine = model.snapshot.routine(id) else { return nil }
        self.model = model
        self.routine = routine
        let today = model.today()
        self.sessionDays = [today]
        self.index = RoutineRun.resumeIndex(routine: routine, log: model.snapshot.routineLog, today: today)
    }

    public var currentStep: RoutineStep? {
        routine.steps.indices.contains(index) ? routine.steps[index] : nil
    }

    public var isFinished: Bool { index >= routine.steps.count }

    /// `Morning · 4 of 11` (STYLEGUIDE §3.7). Clamped so the summary screen still reads `11 of 11`
    /// rather than `12 of 11`.
    public var progressText: String {
        "\(routine.title) · \(min(index + 1, routine.steps.count)) of \(routine.steps.count)"
    }

    public var doneCount: Int { results().values.count { $0 == .done } }
    public var skippedCount: Int { results().values.count { $0 == .skipped } }

    /// Logs the current step and advances (R5). Going back and re-logging replaces the earlier
    /// entry — the reducer dedupes by day, routine, step and device. A failed write (e.g. the
    /// step no longer exists because the template changed under this run) leaves the step in
    /// place instead of silently skipping it. Returns whether the log was recorded.
    @discardableResult
    public func log(_ result: RoutineStepResult) async -> Bool {
        guard let step = currentStep else { return false }
        do {
            try await model.send(.logRoutineStep(routine: routine.id, stepID: step.id, result))
            sessionDays.insert(model.today())
            index += 1
            return true
        } catch {
            return false
        }
    }

    /// Horizontal swipe back = previous step (no swipe filing on routine cards, R2).
    public func back() { index = max(index - 1, 0) }

    /// This session's logged results for this routine, keyed by step id, across every day the
    /// session has touched (see `sessionDays`) and every device (R5 logs are per device).
    public func results() -> [String: RoutineStepResult] {
        var out: [String: RoutineStepResult] = [:]
        for entry in model.snapshot.routineLog
        where sessionDays.contains(entry.day) && entry.routine == routine.title {
            out[entry.step] = entry.result
        }
        return out
    }

    /// The first template step with no log entry for `today`; the step count once every step is
    /// logged. A log entry for a step id the current template no longer has is simply invisible
    /// here — that is what "template edits are tolerated" means (R1): nothing throws, nothing
    /// blocks, the run just resumes at the first step it has no record of today.
    nonisolated public static func resumeIndex(routine: Routine, log: [RoutineLogEntry], today: Day) -> Int {
        let logged = Set(
            log.filter { $0.day == today && $0.routine == routine.title }.map(\.step))
        return routine.steps.firstIndex { !logged.contains($0.id) } ?? routine.steps.count
    }
}

/// Today's progress for one routine (R3), used by the routines home list. Pure and testable —
/// it is the same `RoutineRun.resumeIndex` a run uses to decide where to resume, so the home
/// list and the runner never disagree about where "today" stands.
public enum RoutineProgress: Equatable, Sendable {
    case notStarted
    case inProgress(completed: Int, total: Int)
    case finished

    public static func today(routine: Routine, log: [RoutineLogEntry], today: Day) -> RoutineProgress {
        guard !routine.steps.isEmpty else { return .finished }
        let index = RoutineRun.resumeIndex(routine: routine, log: log, today: today)
        if index == 0 { return .notStarted }
        if index >= routine.steps.count { return .finished }
        return .inProgress(completed: index, total: routine.steps.count)
    }

    /// `Not started` / `3 of 8` / `Finished` — sentence case, terse (STYLEGUIDE §6.1). This
    /// concept is not in the canonical §6.3 table, so the wording lives here rather than in
    /// `DesignSystem.Copy`, which is another target's public API and read-only to this task.
    public var homeText: String {
        switch self {
        case .notStarted: "Not started"
        case .finished: "Finished"
        case let .inProgress(completed, total): "\(completed) of \(total)"
        }
    }
}

extension RoutineStep {
    /// Best-effort match for R4's journaling steps (dreams, achievements, gratitude,
    /// will-do-better). There is no model flag for this — ARCHITECTURE §3 explicitly dropped a
    /// `journalSteps` frontmatter key because "all steps are done/skip only" — so this looks at
    /// the step's own words instead. A false negative only means the ordinary substep checklist
    /// shows in its place; R4 (no text input, ever) holds regardless of this match.
    public var isJournaling: Bool {
        let haystack = ([title] + substeps).joined(separator: " ").lowercased()
        return RoutineStep.journalingKeywords.contains { haystack.contains($0) }
    }

    private static let journalingKeywords = [
        "dream", "achievement", "gratitude", "will-do-better", "will do better", "journal",
    ]
}
