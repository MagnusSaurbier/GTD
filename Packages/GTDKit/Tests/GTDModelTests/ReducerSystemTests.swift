import Testing
import Foundation
import GTDModel
import GTDFixtures

/// R5/R6 routines, A4/A3 config, §10.4 weekly review, A5 archiving, N6 undo-ability,
/// and the determinism guarantee.
struct ReducerSystemTests {
    private let env = TestVault.env()

    // MARK: - R5: the routine log

    private var routineVault: VaultSnapshot {
        TestVault.snapshot(routines: [TestVault.routine("Morning", steps: ["Wake up", "Cold shower"])])
    }

    @Test(arguments: [RoutineStepResult.done, .skipped])
    func loggingAStepWritesOneEntryForThisDayAndDevice(result: RoutineStepResult) throws {
        let vault = routineVault
        let routine = vault.routines[0]
        let reduction = try Reducer.reduce(
            vault, .logRoutineStep(routine: routine.id, stepID: "cold-shower", result), env: env)
        let entry = try #require(reduction.snapshot.routineLog.first)
        #expect(reduction.snapshot.routineLog.count == 1)
        #expect(entry.day == env.today)
        #expect(entry.routine == "Morning")
        #expect(entry.step == "cold-shower")
        #expect(entry.result == result)
        #expect(entry.at == env.now)
        #expect(entry.device == env.deviceID)
        #expect(reduction.extraOps.isEmpty)       // the day's file is written from the snapshot diff
    }

    @Test func reLoggingAStepReplacesTheEarlierEntry() throws {
        let vault = routineVault
        let routine = vault.routines[0]
        let once = try Reducer.reduce(vault, .logRoutineStep(routine: routine.id, stepID: "wake-up", .done), env: env)
        let twice = try Reducer.reduce(once.snapshot, .logRoutineStep(routine: routine.id, stepID: "wake-up", .skipped), env: env)
        #expect(twice.snapshot.routineLog.count == 1)
        #expect(twice.snapshot.routineLog[0].result == .skipped)
    }

    /// N3 — one log file per day **per device**, so two devices never overwrite each other.
    @Test func anotherDeviceKeepsItsOwnEntry() throws {
        let vault = routineVault
        let routine = vault.routines[0]
        let phone = try Reducer.reduce(
            vault, .logRoutineStep(routine: routine.id, stepID: "wake-up", .done), env: TestVault.env(deviceID: "iPhone"))
        let mac = try Reducer.reduce(
            phone.snapshot, .logRoutineStep(routine: routine.id, stepID: "wake-up", .skipped),
            env: TestVault.env(deviceID: "Mac"))
        #expect(mac.snapshot.routineLog.count == 2)
        #expect(Set(mac.snapshot.routineLog.map(\.device)) == ["iPhone", "Mac"])
    }

    /// Yesterday's entry is history — logging today never rewrites it.
    @Test func yesterdaysEntryIsUntouched() throws {
        var vault = routineVault
        let routine = vault.routines[0]
        vault.routineLog = [RoutineLogEntry(
            day: TestVault.day(-1), routine: "Morning", step: "wake-up",
            result: .done, at: TestVault.date(-1), device: "test")]
        let result = try Reducer.reduce(vault, .logRoutineStep(routine: routine.id, stepID: "wake-up", .skipped), env: env)
        #expect(result.snapshot.routineLog.count == 2)
    }

    @Test func loggingAnUnknownRoutineOrStepIsRefused() {
        let vault = routineVault
        let ghost = NoteID(path: "GTD/Routines/Evening.md")
        #expect(TestVault.error(vault, .logRoutineStep(routine: ghost, stepID: "wake-up", .done), env: env)
                == .notFound(ghost))
        #expect(TestVault.error(vault, .logRoutineStep(routine: vault.routines[0].id, stepID: "brush", .done), env: env)
                == .invalid("Unknown routine step brush"))
    }

    @Test func settingARoutineTime() throws {
        let vault = routineVault
        let routine = vault.routines[0]
        let set = try Reducer.reduce(vault, .setRoutineTime(routine: routine.id, DayTime(hour: 6, minute: 30)), env: env)
        #expect(set.snapshot.routines[0].time == DayTime(hour: 6, minute: 30))
        let cleared = try Reducer.reduce(set.snapshot, .setRoutineTime(routine: routine.id, nil), env: env)
        #expect(cleared.snapshot.routines[0].time == nil)
        #expect(TestVault.error(vault, .setRoutineTime(routine: NoteID(path: "GTD/Routines/X.md"), nil), env: env)
                == .notFound(NoteID(path: "GTD/Routines/X.md")))
    }

    /// R6 — routines are not actions, so no list can ever show one.
    @Test func routinesNeverEnterAnActionList() throws {
        let vault = Fixtures.sampleSnapshot
        let today = Fixtures.today
        let routinePaths = Set(vault.routines.map(\.id.path))
        let lists: [[Action]] = [
            Rules.nextList(vault, today: today),
            Rules.onTheGoNextList(vault, today: today),
            Rules.waitingList(vault, today: today),
            Rules.deferredList(vault, today: today),
            Rules.visibleActions(vault, today: today),
        ]
        for list in lists {
            #expect(list.allSatisfy { !routinePaths.contains($0.id.path) })
            #expect(list.allSatisfy { vault.action($0.id) != nil })
        }
        // Logging a routine step does not touch the actions either.
        let routine = vault.routines[0]
        let result = try Reducer.reduce(
            vault, .logRoutineStep(routine: routine.id, stepID: routine.steps[0].id, .done),
            env: Fixtures.reducerEnv())
        #expect(result.snapshot.actions == vault.actions)
    }

    // MARK: - A3/A4: config

    @Test func configIsValidatedAndDeduplicated() throws {
        let vault = TestVault.snapshot()
        var config = GTDConfig.default
        config.contexts = ["mac", "mac", "phone"]
        config.onTheGoContexts = ["phone", "phone"]
        let result = try Reducer.reduce(vault, .updateConfig(config), env: env)
        #expect(result.snapshot.config.contexts == ["mac", "phone"])
        #expect(result.snapshot.config.onTheGoContexts == ["phone"])

        var zeroCap = GTDConfig.default
        zeroCap.nextCap = 0
        #expect(TestVault.error(vault, .updateConfig(zeroCap), env: env)
                == .invalid("Next cap must be at least 1"))

        var empty = GTDConfig.default
        empty.contexts = []
        #expect(TestVault.error(vault, .updateConfig(empty), env: env)
                == .invalid("At least one context is required"))

        var stray = GTDConfig.default
        stray.onTheGoContexts = ["phone", "teleport"]
        #expect(TestVault.error(vault, .updateConfig(stray), env: env)
                == .invalid("Unknown context: teleport"))
    }

    /// Lowering the cap below the current count is allowed — the weekly review is where the
    /// user works the list back down (§10.2). The cap only blocks *new* Next slots.
    @Test func loweringTheCapBelowTheCurrentCountIsAllowed() throws {
        var vault = TestVault.nextOccupied(10)
        var config = vault.config
        config.nextCap = 5
        let result = try Reducer.reduce(vault, .updateConfig(config), env: env)
        #expect(Rules.capSignal(result.snapshot, today: env.today)?.step == .overdue)
        vault = result.snapshot
        #expect(TestVault.error(vault, .createAction(ActionDraft(title: "Noch eins", status: .next)), env: env)
                == .nextCapReached(cap: 5))
    }

    // MARK: - §10.4: the weekly review note

    @Test func savingAReviewStoresItWithoutWritingMarkdown() throws {
        let review = WeeklyReview(year: 2026, week: 38, goalForNextWeek: "Letter drafted")
        let result = try Reducer.reduce(TestVault.snapshot(), .saveWeeklyReview(review), env: env)
        let saved = try #require(result.snapshot.lastReview)
        #expect(saved.week == 38)
        #expect(saved.savedAt == env.now)
        #expect(saved.noteID().path == "GTD/Reviews/2026/KW 38.md")
        // T00-4: GTDServices encodes the note from the changed `lastReview`.
        #expect(result.extraOps.isEmpty)
    }

    @Test(arguments: [0, 54, -1])
    func animplausibleWeekIsRefused(week: Int) {
        #expect(TestVault.error(TestVault.snapshot(), .saveWeeklyReview(WeeklyReview(year: 2026, week: week)), env: env)
                == .invalid("Week \(week) is not a calendar week"))
    }

    @Test func animplausibleYearIsRefused() {
        #expect(TestVault.error(TestVault.snapshot(), .saveWeeklyReview(WeeklyReview(year: 1900, week: 1)), env: env)
                == .invalid("Year 1900 is not a plausible year"))
    }

    // MARK: - A5: archiving

    @Test func archivingMovesOnlyClosedNotesOlderThanThirtyDays() throws {
        let vault = TestVault.snapshot(actions: [
            TestVault.action("Alt erledigt", .done, completed: -31),
            TestVault.action("Genau dreißig", .done, completed: -30),      // not yet
            TestVault.action("Neu erledigt", .done, completed: -1),
            TestVault.action("Alt verworfen", .legacyTrashed, completed: -40),
            TestVault.action("Offen", .next, modified: -100),
        ])
        let result = try Reducer.reduce(vault, .archiveCompleted, env: env)

        #expect(result.snapshot.actions.map(\.title).sorted()
                == ["Genau dreißig", "Neu erledigt", "Offen"])
        // R-1 — a note still carrying the legacy `status: trash` is not archive material:
        // it goes to `GTD/Trash/`, where everything the user threw away lives (I4c).
        #expect(result.extraOps == [
            .move(from: "Actions/Alt erledigt.md", to: "Archive/2026/08/Alt erledigt.md"),
            .move(from: "Actions/Alt verworfen.md", to: "GTD/Trash/Alt verworfen.md"),
        ])
    }

    @Test func archivingAnEmptyVaultChangesNothing() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action("Offen", .next)])
        let result = try Reducer.reduce(vault, .archiveCompleted, env: env)
        #expect(result.snapshot == vault)
        #expect(result.extraOps.isEmpty)
    }

    /// A hand-edited note without `completedDate` falls back to its modification date; with
    /// neither, the app does not guess when it was closed.
    @Test func archiveFallsBackToTheModificationDate() throws {
        var old = TestVault.action("Ohne Datum", .done, modified: -60)
        old.completedDate = nil
        var undated = TestVault.action("Ganz ohne", .done, modified: -60)
        undated.completedDate = nil
        undated.modified = nil

        let result = try Reducer.reduce(TestVault.snapshot(actions: [old, undated]), .archiveCompleted, env: env)
        #expect(result.snapshot.actions.map(\.title) == ["Ganz ohne"])
    }

    // MARK: - N6: what can be undone

    @Test func undoCoversFilingAndStatusChangesOnly() {
        let id = TestVault.actionID("X")
        let undoable: [GTDCommand] = [
            .editInboxText(TestVault.layout.inboxPath(stamp: "2026-09-19 081204"), "x"),
            .fileInbox(TestVault.layout.inboxPath(stamp: "2026-09-19 081204"), .trash),
            .deferInboxToReview(TestVault.layout.inboxPath(stamp: "2026-09-19 081204"), reason: "r"),
            .createAction(ActionDraft(title: "X")),
            .updateAction(TestVault.action("X")),
            .setStatus(id, .next, waiting: nil),
            .complete(id),
            .toggleCheckbox(id, index: 0),
            .convertActionToProject(id, ProjectDraft(title: "P")),
            .createArea(title: "A"),
            .createProject(ProjectDraft(title: "P")),
            .updateProject(TestVault.project("P")),
            .promoteStep(project: TestVault.project("P").id, stepIndex: 0, ActionDraft(title: "X")),
        ]
        let notUndoable: [GTDCommand] = [
            .updateConfig(.default),
            .logRoutineStep(routine: NoteID(path: "GTD/Routines/Morning.md"), stepID: "wake-up", .done),
            .setRoutineTime(routine: NoteID(path: "GTD/Routines/Morning.md"), nil),
            .saveWeeklyReview(WeeklyReview(year: 2026, week: 38)),
            .archiveCompleted,
        ]
        for command in undoable { #expect(Rules.isUndoable(command), "\(command)") }
        for command in notUndoable { #expect(!Rules.isUndoable(command), "\(command)") }
    }

    // MARK: - Determinism

    @Test func everyCommandIsDeterministic() throws {
        let vault = Fixtures.sampleSnapshot
        let env = Fixtures.reducerEnv()
        let inbox = try #require(Rules.inboxQueue(vault).first)
        let someday = try #require(vault.actions.first { $0.status == .someday && $0.deferDate == nil })
        let routine = try #require(vault.routines.first)
        let step = try #require(routine.steps.first)
        let project = Fixtures.daadProject

        let commands: [GTDCommand] = [
            .editInboxText(inbox.id, "edited"),
            .fileInbox(inbox.id, .trash),
            .fileInbox(inbox.id, .action(ActionDraft(title: "Frisch", status: .someday))),
            .fileInbox(inbox.id, .knowledge(folder: "Studium", title: "Notiz")),
            .deferInboxToReview(inbox.id, reason: "needs thinking"),
            .createAction(ActionDraft(title: "Brand new action", status: .someday)),
            .updateAction(someday),
            .setStatus(someday.id, .next, waiting: nil),
            .trashAction(someday.id),
            .setStatus(someday.id, .waiting, waiting: WaitingInfo(who: "Lena", followUp: Fixtures.day(7))),
            .complete(someday.id),
            .convertActionToProject(someday.id, ProjectDraft(title: "Ein Projekt")),
            .createArea(title: "Gesundheit"),
            .createProject(ProjectDraft(title: "Zahnarzt", newAreaTitle: "Gesundheit")),
            .updateProject(project),
            .promoteStep(project: project.id, stepIndex: 2, ActionDraft(title: "Prof. Weber fragen")),
            .logRoutineStep(routine: routine.id, stepID: step.id, .done),
            .setRoutineTime(routine: routine.id, DayTime(hour: 6, minute: 30)),
            .updateConfig(vault.config),
            .saveWeeklyReview(WeeklyReview(year: 2026, week: 38)),
            .archiveCompleted,
        ]

        for command in commands {
            let first = try Reducer.reduce(vault, command, env: env)
            let second = try Reducer.reduce(vault, command, env: env)
            #expect(first.snapshot == second.snapshot, "\(command)")
            #expect(first.prompts == second.prompts, "\(command)")
            #expect(first.extraOps == second.extraOps, "\(command)")
        }
    }

    /// Two actions that differ only in their `id` must not make a list flip order.
    @Test func listsHaveATotalOrder() {
        let same = (0..<5).map { index in
            TestVault.action("Gleich \(index)", .next, created: -3)
        }
        let vault = TestVault.snapshot(actions: same.reversed())
        let once = Rules.nextList(vault, today: TestVault.today).map(\.id.path)
        let twice = Rules.nextList(TestVault.snapshot(actions: same), today: TestVault.today).map(\.id.path)
        #expect(once == twice)
        #expect(once == same.map(\.id.path).sorted())
    }
}
