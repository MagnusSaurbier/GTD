import Testing
import Foundation
import GTDModel
import GTDFixtures

/// Every `GTDCommand` does something sensible against the realistic sample vault.
/// The rule-by-rule tables live in `ReducerInboxTests`, `ReducerActionTests`,
/// `ReducerProjectTests`, `ReducerSystemTests` and `RulesTests`.
struct ReducerSmokeTests {
    private let env = Fixtures.reducerEnv()
    private var snapshot: VaultSnapshot { Fixtures.sampleSnapshot }

    @Test func everyCommandIsHandled() throws {
        let inbox = try #require(Rules.inboxQueue(snapshot).first)
        let someday = try #require(snapshot.actions.first { $0.status == .someday })
        let routine = try #require(snapshot.routines.first)
        let step = try #require(routine.steps.first)

        let commands: [GTDCommand] = [
            .editInboxText(inbox.id, "edited"),
            .fileInbox(inbox.id, .trash),
            .deferInboxToReview(inbox.id, reason: "needs thinking"),
            .createAction(ActionDraft(
                title: "Brand new action", status: .someday, what: "Anfangen")),
            .setStatus(someday.id, .next, waiting: nil),
            .trashAction(someday.id),
            .createArea(title: "Gesundheit"),
            .createProject(ProjectDraft(title: "Zahnarzt", newAreaTitle: "Gesundheit")),
            .logRoutineStep(routine: routine.id, stepID: step.id, .done),
            .setRoutineTime(routine: routine.id, DayTime(hour: 6, minute: 30)),
            .updateConfig(snapshot.config),
            .saveWeeklyReview(WeeklyReview(year: 2026, week: 38)),
            .archiveCompleted,
        ]
        for command in commands {
            _ = try Reducer.reduce(snapshot, command, env: env)
        }
    }

    @Test func reducerIsDeterministic() throws {
        let command = GTDCommand.createAction(ActionDraft(
            title: "Deterministic", status: .someday, what: "Tun"))
        let a = try Reducer.reduce(snapshot, command, env: env)
        let b = try Reducer.reduce(snapshot, command, env: env)
        #expect(a.snapshot == b.snapshot)
        #expect(a.prompts == b.prompts)
        #expect(a.extraOps == b.extraOps)
    }

    @Test func onlyActiveProjectsPutActionsIntoNext() {
        let draft = ActionDraft(title: "CV updaten", status: .next, project: Fixtures.sideJobProject.id)
        #expect(throws: GTDError.self) {
            try Reducer.reduce(snapshot, .createAction(draft), env: env)
        }
    }

    @Test func leavingActiveDemotesNextActions() throws {
        var project = Fixtures.daadProject
        project.status = .onHold
        let before = snapshot.actions.count { $0.project == project.id && $0.status.countsTowardCap }
        #expect(before > 0)
        let result = try Reducer.reduce(snapshot, .updateProject(project), env: env)
        let after = result.snapshot.actions.count { $0.project == project.id && $0.status.countsTowardCap }
        #expect(after == 0)
    }

    @Test func titleCollisionIsReported() {
        let existing = Fixtures.actions[0].title
        #expect(throws: GTDError.titleCollision(existing)) {
            try Reducer.reduce(snapshot, .createAction(ActionDraft(title: existing)), env: env)
        }
    }

    @Test func archiveMovesOldDoneActionsOutOfTheSnapshot() throws {
        let candidates = Rules.archiveCandidates(snapshot, today: env.today)
        #expect(!candidates.isEmpty)
        let result = try Reducer.reduce(snapshot, .archiveCompleted, env: env)
        #expect(result.extraOps.count == candidates.count)
        for candidate in candidates {
            #expect(result.snapshot.action(candidate.id) == nil)
        }
    }

    @Test func togglingACheckboxRewritesOnlyThatLine() throws {
        let action = try #require(snapshot.actions.first { $0.checkboxes.count >= 2 })
        let result = try Reducer.reduce(snapshot, .toggleCheckbox(action.id, index: 0), env: env)
        let updated = try #require(result.snapshot.action(action.id))
        #expect(updated.checkboxes[0].done != action.checkboxes[0].done)
        #expect(updated.checkboxes[1].done == action.checkboxes[1].done)
    }

    @Test func routineStepReLogReplacesTheEntry() throws {
        let routine = try #require(snapshot.routines.first)
        let step = try #require(routine.steps.first)
        let once = try Reducer.reduce(snapshot, .logRoutineStep(routine: routine.id, stepID: step.id, .done), env: env)
        let twice = try Reducer.reduce(once.snapshot, .logRoutineStep(routine: routine.id, stepID: step.id, .skipped), env: env)
        let entries = twice.snapshot.routineLog.filter {
            $0.day == env.today && $0.routine == routine.title && $0.step == step.id
                && $0.device == env.deviceID
        }
        #expect(entries.count == 1)
        #expect(entries.first?.result == .skipped)
    }
}
