import Testing
import Foundation
import GTDModel
import GTDFixtures

/// A1, A3, A4, A5, W1, D1 and the completion rules P4/P5 — one table per rule.
struct ReducerActionTests {
    private let env = TestVault.env()

    // MARK: - A3: the Next cap

    struct CapCase: Sendable, CustomStringConvertible {
        let occupied: Int
        let cap: Int
        let status: ActionStatus
        let refused: Bool
        var description: String { "\(occupied)/\(cap) + \(status.rawValue) ⇒ \(refused ? "refused" : "allowed")" }
    }

    @Test(arguments: [
        CapCase(occupied: 0, cap: 15, status: .next, refused: false),
        CapCase(occupied: 13, cap: 15, status: .next, refused: false),
        CapCase(occupied: 14, cap: 15, status: .next, refused: false),   // the last free slot
        CapCase(occupied: 15, cap: 15, status: .next, refused: true),    // exactly at the cap
        CapCase(occupied: 15, cap: 15, status: .inProgress, refused: true),
        CapCase(occupied: 16, cap: 15, status: .next, refused: true),    // hand-edited, still refused
        CapCase(occupied: 15, cap: 15, status: .backlog, refused: false),
        CapCase(occupied: 15, cap: 15, status: .maybe, refused: false),
        CapCase(occupied: 15, cap: 15, status: .waiting, refused: false),
        CapCase(occupied: 0, cap: 1, status: .next, refused: false),
        CapCase(occupied: 1, cap: 1, status: .next, refused: true),
    ])
    func theCapBlocksOnlyNewNextSlots(testCase: CapCase) {
        let vault = TestVault.nextOccupied(testCase.occupied, cap: testCase.cap)
        let draft = ActionDraft(
            title: "One more", status: testCase.status,
            waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(7)))
        let error = TestVault.error(vault, .createAction(draft), env: env)
        #expect((error == .nextCapReached(cap: testCase.cap)) == testCase.refused, "\(testCase)")
    }

    @Test func demotingIsAlwaysAllowedEvenAboveTheCap() throws {
        let vault = TestVault.nextOccupied(17)      // only reachable by editing files
        #expect(Rules.capSignal(vault)?.step == .overdue)
        let id = TestVault.actionID("Next 0")
        let result = try Reducer.reduce(vault, .setStatus(id, .backlog, waiting: nil), env: env)
        #expect(Rules.countsTowardCap(result.snapshot) == 16)
    }

    @Test func promotingFromBacklogAtTheCapIsRefused() {
        var vault = TestVault.nextOccupied(15)
        vault.actions.append(TestVault.action("Später", .backlog))
        let error = TestVault.error(vault, .setStatus(TestVault.actionID("Später"), .next, waiting: nil), env: env)
        #expect(error == .nextCapReached(cap: 15))
    }

    // MARK: - W1: waiting needs who and follow-up

    @Test func settingWaitingRequiresBothHalves() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action("Deposit refund")])
        let id = TestVault.actionID("Deposit refund")

        #expect(TestVault.error(vault, .setStatus(id, .waiting, waiting: nil), env: env) == .waitingInfoRequired)
        #expect(TestVault.error(vault, .setStatus(id, .waiting, waiting:
            WaitingInfo(who: "   ", followUp: TestVault.day(7))), env: env) == .waitingInfoRequired)

        let result = try Reducer.reduce(vault, .setStatus(id, .waiting, waiting:
            WaitingInfo(who: " Herr Kramer ", followUp: TestVault.day(7))), env: env)
        let action = try #require(result.snapshot.action(id))
        #expect(action.waitingFor == "Herr Kramer")
        #expect(action.followUpDate == TestVault.day(7))
    }

    @Test(arguments: [ActionStatus.next, .backlog, .maybe, .done, .trash])
    func leavingWaitingClearsBothHalves(status: ActionStatus) throws {
        let waiting = TestVault.action(
            "Reference letter", .waiting,
            waiting: WaitingInfo(who: "Prof. Weber", followUp: TestVault.day(-9)))
        let vault = TestVault.snapshot(actions: [waiting])
        let result = try Reducer.reduce(vault, .setStatus(waiting.id, status, waiting: nil), env: env)
        let action = try #require(result.snapshot.action(waiting.id))
        #expect(action.waitingFor == nil)
        #expect(action.followUpDate == nil)
    }

    // MARK: - D1: defer

    @Test func aDeferredActionCannotOccupyANextSlot() {
        let vault = TestVault.snapshot(actions: [TestVault.action("Plan the timetable", .backlog)])
        let id = TestVault.actionID("Plan the timetable")
        var deferred = vault.action(id)!
        deferred.deferDate = TestVault.day(10)
        deferred.status = .next

        #expect(TestVault.error(vault, .updateAction(deferred), env: env)
                == .invalid("A deferred action cannot sit in Next"))
        #expect(TestVault.error(vault, .createAction(ActionDraft(
            title: "Später", status: .next, deferDate: TestVault.day(3))), env: env)
                == .invalid("A deferred action cannot sit in Next"))
    }

    @Test func aDeferDateInThePastOrTodayIsFineInNext() throws {
        let vault = TestVault.snapshot()
        for offset in [-1, 0] {
            let result = try Reducer.reduce(vault, .createAction(ActionDraft(
                title: "Zurück \(offset)", status: .next, deferDate: TestVault.day(offset))), env: env)
            #expect(result.snapshot.actions.count == 1)
        }
    }

    /// A vault edited by hand into the contradiction stays editable — the rule refuses only the
    /// *new* contradiction.
    @Test func anExistingDeferredNextActionCanStillBeEdited() throws {
        let stray = TestVault.action("Hand-edited", .next, deferDate: TestVault.day(10))
        let vault = TestVault.snapshot(actions: [stray])
        var edited = stray
        edited.why = "Repaired in the app"
        let result = try Reducer.reduce(vault, .updateAction(edited), env: env)
        #expect(result.snapshot.action(stray.id)?.why == "Repaired in the app")
        // …and demoting it works.
        let demoted = try Reducer.reduce(vault, .setStatus(stray.id, .backlog, waiting: nil), env: env)
        #expect(demoted.snapshot.action(stray.id)?.status == .backlog)
    }

    // MARK: - A4: contexts are a closed list

    @Test func unknownContextsAreRefusedAndDuplicatesCollapse() throws {
        let vault = TestVault.snapshot()
        #expect(TestVault.error(vault, .createAction(ActionDraft(
            title: "Mit Kontext", contexts: ["mac", "urgent"])), env: env)
                == .invalid("Unknown context: urgent"))

        let result = try Reducer.reduce(vault, .createAction(ActionDraft(
            title: "Mit Kontext", contexts: ["mac", "mac", " phone "])), env: env)
        #expect(result.snapshot.actions.first?.contexts == ["mac", "phone"])
    }

    /// A migrated note may carry a context the config does not know; editing it must not fail.
    @Test func contextsAlreadyInTheNoteSurviveAnEdit() throws {
        let legacy = TestVault.action("Alt", .backlog, contexts: ["tum-stammgelände"])
        let vault = TestVault.snapshot(actions: [legacy])
        var edited = legacy
        edited.contexts = ["tum-stammgelände", "mac"]
        let result = try Reducer.reduce(vault, .updateAction(edited), env: env)
        #expect(result.snapshot.action(legacy.id)?.contexts == ["tum-stammgelände", "mac"])
    }

    // MARK: - A1: the title is the file name

    @Test func titlesAreSanitisedAndNeverEmpty() throws {
        let result = try Reducer.reduce(
            TestVault.snapshot(),
            .createAction(ActionDraft(title: "Steuer/Erklärung: 2026?")), env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.title == "Steuer Erklärung 2026")
        #expect(action.id.path == "Actions/Steuer Erklärung 2026.md")
        #expect(TestVault.error(TestVault.snapshot(), .createAction(ActionDraft(title: " \n ")), env: env)
                == .invalid("A title is required"))
    }

    @Test func renamingAnActionMovesItsFileAndFollowsTheProjectStep() throws {
        let project = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Write the letter", promotedTo: TestVault.actionID("Letter")),
        ])
        let original = TestVault.action("Letter", .next, project: project.id)
        let vault = TestVault.snapshot(actions: [original], projects: [project])

        var renamed = original
        renamed.title = "Motivation letter"
        let result = try Reducer.reduce(vault, .updateAction(renamed), env: env)

        let newID = TestVault.actionID("Motivation letter")
        #expect(result.snapshot.action(newID)?.title == "Motivation letter")
        #expect(result.snapshot.action(original.id) == nil)
        #expect(result.extraOps == [.move(from: original.id.path, to: newID.path)])
        #expect(result.snapshot.projects[0].steps[0].promotedTo == newID)
        // The one thing the new snapshot cannot say by itself: this note was renamed, not
        // deleted. Whoever is looking at it follows this instead of concluding it is gone.
        #expect(result.renames.resolve(original.id) == newID)
    }

    /// An edit that leaves the title alone renames nothing, so there is nothing to follow.
    @Test func anEditThatKeepsTheTitleReportsNoRename() throws {
        let original = TestVault.action("Letter", .next)
        var edited = original
        edited.why = "Because the deadline is in March"
        let result = try Reducer.reduce(
            TestVault.snapshot(actions: [original]), .updateAction(edited), env: env)
        #expect(result.renames.isEmpty)
        #expect(result.extraOps.isEmpty)
    }

    @Test func renamingOntoAnExistingTitleIsACollision() {
        let a = TestVault.action("Letter")
        let b = TestVault.action("Motivation letter")
        var renamed = a
        renamed.title = "Motivation letter"
        #expect(TestVault.error(TestVault.snapshot(actions: [a, b]), .updateAction(renamed), env: env)
                == .titleCollision("Motivation letter"))
    }

    @Test func editingAnActionKeepsItsCaptureDateAndRefreshesModified() throws {
        let original = TestVault.action("Letter", created: -30, modified: -30)
        var edited = original
        edited.created = Date(timeIntervalSince1970: 0)     // the UI must not be able to rewrite it
        edited.why = "changed"
        let result = try Reducer.reduce(TestVault.snapshot(actions: [original]), .updateAction(edited), env: env)
        #expect(result.snapshot.action(original.id)?.created == original.created)
        #expect(result.snapshot.action(original.id)?.modified == env.now)
    }

    // MARK: - §1: no lying defaults

    @Test(arguments: [0, -5])
    func aTimeEstimateOfZeroIsNeverStored(estimate: Int) throws {
        let result = try Reducer.reduce(
            TestVault.snapshot(),
            .createAction(ActionDraft(title: "Ohne Schätzung", timeEstimate: estimate)), env: env)
        #expect(result.snapshot.actions.first?.timeEstimate == nil)
    }

    // MARK: - A5 / P4 / P5: completion

    private func projectVault() -> VaultSnapshot {
        let project = TestVault.project("DAAD", steps: [
            ProjectStep(text: "Collect transcripts", promotedTo: TestVault.actionID("Transcripts")),
            ProjectStep(text: "Write the letter"),
        ])
        return TestVault.snapshot(
            actions: [TestVault.action("Transcripts", .next, project: project.id)],
            projects: [project])
    }

    @Test func completingAProjectActionLogsTicksAndPrompts() throws {
        let vault = projectVault()
        let id = TestVault.actionID("Transcripts")
        let result = try Reducer.reduce(vault, .complete(id), env: env)

        let action = try #require(result.snapshot.action(id))
        #expect(action.status == .done)
        #expect(action.completedDate == env.now)
        let project = try #require(result.snapshot.projects.first)
        #expect(project.log.last == LogEntry(day: env.today, text: "Transcripts"))   // P6
        #expect(project.steps[0].done)                                               // P4
        #expect(result.prompts == [.whatsNext(project: project.id)])                 // P5
        // A5 — it disappears from every list at once.
        #expect(!Rules.visibleActions(result.snapshot, today: env.today).contains { $0.id == id })
    }

    @Test func completingTwiceDoesNotLogTwice() throws {
        let once = try Reducer.reduce(projectVault(), .complete(TestVault.actionID("Transcripts")), env: env)
        let twice = try Reducer.reduce(once.snapshot, .complete(TestVault.actionID("Transcripts")), env: env)
        #expect(twice.snapshot == once.snapshot)
        #expect(twice.prompts.isEmpty)
    }

    @Test func completingThroughSetStatusBehavesTheSame() throws {
        let viaComplete = try Reducer.reduce(projectVault(), .complete(TestVault.actionID("Transcripts")), env: env)
        let viaStatus = try Reducer.reduce(
            projectVault(), .setStatus(TestVault.actionID("Transcripts"), .done, waiting: nil), env: env)
        #expect(viaStatus.snapshot == viaComplete.snapshot)
        #expect(viaStatus.prompts == viaComplete.prompts)
    }

    @Test func completingThroughUpdateActionBehavesTheSame() throws {
        let vault = projectVault()
        var done = try #require(vault.action(TestVault.actionID("Transcripts")))
        done.status = .done
        let viaUpdate = try Reducer.reduce(vault, .updateAction(done), env: env)
        let viaComplete = try Reducer.reduce(vault, .complete(done.id), env: env)
        #expect(viaUpdate.snapshot == viaComplete.snapshot)
        #expect(viaUpdate.prompts == viaComplete.prompts)
    }

    @Test func completingAnActionWithoutAProjectPromptsNothing() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action("Fahrradlicht", .next)])
        let result = try Reducer.reduce(vault, .complete(TestVault.actionID("Fahrradlicht")), env: env)
        #expect(result.prompts.isEmpty)
    }

    /// P5 — a project that is not active cannot take a next step, so there is nothing to ask.
    @Test(arguments: [ProjectStatus.onHold, .someday, .done])
    func completingInAnInactiveProjectStillLogsButDoesNotPrompt(status: ProjectStatus) throws {
        var vault = projectVault()
        vault.projects[0].status = status
        vault.actions[0].status = .backlog          // P3: it could not be in Next anyway
        let result = try Reducer.reduce(vault, .complete(vault.actions[0].id), env: env)
        #expect(result.prompts.isEmpty)
        #expect(result.snapshot.projects[0].log.count == 1)
    }

    @Test func trashingClosesTheActionAndReopeningClearsTheDate() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action("Podcast app", .maybe)])
        let id = TestVault.actionID("Podcast app")
        let trashed = try Reducer.reduce(vault, .setStatus(id, .trash, waiting: nil), env: env)
        #expect(trashed.snapshot.action(id)?.completedDate == env.now)     // A5: it has a closing date
        #expect(!Rules.visibleActions(trashed.snapshot, today: env.today).contains { $0.id == id })

        let reopened = try Reducer.reduce(trashed.snapshot, .setStatus(id, .backlog, waiting: nil), env: env)
        #expect(reopened.snapshot.action(id)?.completedDate == nil)        // no lying date
    }

    // MARK: - A2: checkboxes

    @Test func togglingRewritesOnlyOneLine() throws {
        let action = TestVault.action(
            "Vortrag", .next,
            what: "- [ ] Outline five slides\nSome prose\n- [x] Rehearse once")
        let vault = TestVault.snapshot(actions: [action])
        let result = try Reducer.reduce(vault, .toggleCheckbox(action.id, index: 1), env: env)
        let updated = try #require(result.snapshot.action(action.id))
        #expect(updated.checkboxes.map(\.done) == [false, false])
        #expect(updated.what.contains("Some prose"))
        #expect(updated.modified == env.now)
    }

    @Test(arguments: [-1, 2, 99])
    func togglingAMissingCheckboxIsInvalid(index: Int) {
        let action = TestVault.action("Vortrag", .next, what: "- [ ] A\n- [ ] B")
        let error = TestVault.error(TestVault.snapshot(actions: [action]),
                                    .toggleCheckbox(action.id, index: index), env: env)
        #expect(error == .invalid("No checkbox at index \(index)"))
    }

    // MARK: - Unknown ids

    @Test func commandsOnUnknownActionsAreNotFound() {
        let ghost = TestVault.actionID("Ghost")
        let vault = TestVault.snapshot()
        let commands: [GTDCommand] = [
            .updateAction(TestVault.action("Ghost")),
            .setStatus(ghost, .next, waiting: nil),
            .complete(ghost),
            .toggleCheckbox(ghost, index: 0),
            .convertActionToProject(ghost, ProjectDraft(title: "P")),
        ]
        for command in commands {
            #expect(TestVault.error(vault, command, env: env) == .notFound(ghost), "\(command)")
        }
    }

    // MARK: - Against the realistic vault

    @Test func theSampleVaultSitsOneBelowTheCapAndFillsUpExactlyOnce() throws {
        let env = Fixtures.reducerEnv()
        let vault = Fixtures.sampleSnapshot
        #expect(Rules.countsTowardCap(vault) == vault.config.nextCap - 1)

        let filled = try Reducer.reduce(
            vault, .createAction(ActionDraft(title: "Fifteenth", status: .next)), env: env)
        #expect(Rules.countsTowardCap(filled.snapshot) == vault.config.nextCap)
        #expect(Rules.capSignal(filled.snapshot)?.step == .attention)

        #expect(TestVault.error(filled.snapshot,
                                .createAction(ActionDraft(title: "Sixteenth", status: .next)), env: env)
                == .nextCapReached(cap: 15))
    }
}
