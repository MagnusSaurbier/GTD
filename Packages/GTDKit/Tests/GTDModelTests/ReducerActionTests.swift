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
        CapCase(occupied: 15, cap: 15, status: .someday, refused: false),
        CapCase(occupied: 15, cap: 15, status: .done, refused: false),
        CapCase(occupied: 15, cap: 15, status: .waiting, refused: false),
        // #87 — handed to an agent / waiting for review: no cap slot.
        CapCase(occupied: 15, cap: 15, status: .agent, refused: false),
        CapCase(occupied: 15, cap: 15, status: .review, refused: false),
        CapCase(occupied: 0, cap: 1, status: .next, refused: false),
        CapCase(occupied: 1, cap: 1, status: .next, refused: true),
    ])
    func theCapBlocksOnlyNewNextSlots(testCase: CapCase) {
        let vault = TestVault.nextOccupied(testCase.occupied, cap: testCase.cap)
        // R-3 — a complete card, so the table is about the cap and nothing else.
        let draft = ActionDraft(
            title: "One more", status: testCase.status, contexts: ["mac"], timeEstimate: 10,
            waiting: WaitingInfo(who: "Lena", followUp: TestVault.day(7)),
            why: "It is the last slot.", what: "Do it.")
        let error = TestVault.error(vault, .createAction(draft), env: env)
        #expect((error == .nextCapReached(cap: testCase.cap)) == testCase.refused, "\(testCase)")
    }

    @Test func demotingIsAlwaysAllowedEvenAboveTheCap() throws {
        let vault = TestVault.nextOccupied(17)      // only reachable by editing files
        #expect(Rules.capSignal(vault, today: env.today)?.step == .overdue)
        let id = TestVault.actionID("Next 0")
        let result = try Reducer.reduce(vault, .setStatus(id, .someday, waiting: nil), env: env)
        #expect(Rules.countsTowardCap(result.snapshot, today: env.today) == 16)
    }

    /// #87 — a Next item handed to an agent frees its slot; taking it back (review → in
    /// progress) needs one again, and at the cap that is refused like any promotion.
    @Test func handingToAnAgentFreesTheSlotAndTakingItBackNeedsOne() throws {
        var vault = TestVault.nextOccupied(15)
        // A complete note, so the refusal at the end is about the cap and nothing else (R-3).
        vault.actions[0] = TestVault.action(
            "Next 0", .next, contexts: ["mac"], timeEstimate: 10, why: "It matters.", what: "Do it.")
        let id = TestVault.actionID("Next 0")
        let handed = try Reducer.reduce(vault, .setStatus(id, .agent, waiting: nil), env: env)
        #expect(Rules.countsTowardCap(handed.snapshot, today: env.today) == 14)
        let review = try Reducer.reduce(handed.snapshot, .setStatus(id, .review, waiting: nil), env: env)
        #expect(review.snapshot.action(id)?.status == .review)
        let filled = try Reducer.reduce(review.snapshot, .createAction(ActionDraft(
            title: "Fifteenth", status: .next, contexts: ["mac"], timeEstimate: 10,
            why: "The last slot.", what: "Do it.")), env: env)
        #expect(TestVault.error(filled.snapshot, .setStatus(id, .inProgress, waiting: nil), env: env)
            == .nextCapReached(cap: 15))
    }

    /// #87 — handing a bare Someday note to an agent asks for nothing (like demoting).
    @Test func aBareSomedayNoteCanBeHandedToAnAgent() throws {
        var vault = TestVault.nextOccupied(0)
        vault.actions.append(TestVault.action("Idee", .someday))
        let id = TestVault.actionID("Idee")
        let result = try Reducer.reduce(vault, .setStatus(id, .agent, waiting: nil), env: env)
        #expect(result.snapshot.action(id)?.status == .agent)
    }

    @Test func promotingFromSomedayAtTheCapIsRefused() {
        var vault = TestVault.nextOccupied(15)
        vault.actions.append(TestVault.action(
            "Später", .someday, contexts: ["mac"], timeEstimate: 10,
            why: "It matters.", what: "Do it."))
        let error = TestVault.error(vault, .setStatus(TestVault.actionID("Später"), .next, waiting: nil), env: env)
        #expect(error == .nextCapReached(cap: 15))
    }

    // MARK: - W1/D39: waiting needs a follow-up date; who is optional

    @Test func settingWaitingRequiresTheFollowUpDate() throws {
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Deposit refund", what: "Nachfragen")])
        let id = TestVault.actionID("Deposit refund")

        #expect(TestVault.error(vault, .setStatus(id, .waiting, waiting: nil), env: env)
                == .missingFields([.followUpDate]))

        let result = try Reducer.reduce(vault, .setStatus(id, .waiting, waiting:
            WaitingInfo(who: " Herr Kramer ", followUp: TestVault.day(7))), env: env)
        let action = try #require(result.snapshot.action(id))
        #expect(action.waitingFor == "Herr Kramer")
        #expect(action.followUpDate == TestVault.day(7))
    }

    /// D39 — a wait on a process has nobody to name, and the note says so by staying silent.
    @Test func waitingWithoutAWhoIsAllowed() throws {
        let vault = TestVault.snapshot(
            actions: [TestVault.action("Deposit refund", what: "Nachfragen")])
        let id = TestVault.actionID("Deposit refund")
        let result = try Reducer.reduce(vault, .setStatus(id, .waiting, waiting:
            WaitingInfo(who: "  ", followUp: TestVault.day(7))), env: env)
        let action = try #require(result.snapshot.action(id))
        #expect(action.waitingFor == nil)
        #expect(action.waiting == WaitingInfo(who: nil, followUp: TestVault.day(7)))
    }

    /// M2 imports every legacy waiting item without a follow-up date. Such a note is already in
    /// its tier, so an edit to it (context, time, text) is not judged (R-3) and keeps the
    /// halves it has; only *entering* waiting asks for the date.
    @Test func editingAWaitingNoteWithoutAFollowUpDateIsAllowedAndKeepsItsWho() throws {
        var imported = TestVault.action(
            "Coaching contract", .waiting,
            waiting: WaitingInfo(who: "Coach", followUp: TestVault.day(3)),
            what: "Ask about the locked cards")
        imported.followUpDate = nil
        let vault = TestVault.snapshot(actions: [imported])

        var edited = imported
        edited.contexts = ["mac"]
        edited.timeEstimate = 10
        let result = try Reducer.reduce(vault, .updateAction(edited), env: env)
        let action = try #require(result.snapshot.action(imported.id))
        #expect(action.contexts == ["mac"])
        #expect(action.timeEstimate == 10)
        #expect(action.waitingFor == "Coach")
        #expect(action.followUpDate == nil)

        // Staying in waiting through `setStatus` is not an entry either.
        let same = try Reducer.reduce(vault, .setStatus(imported.id, .waiting, waiting: nil), env: env)
        #expect(same.snapshot.action(imported.id)?.waitingFor == "Coach")
    }

    @Test(arguments: [ActionStatus.next, .someday, .done])
    func leavingWaitingClearsBothHalves(status: ActionStatus) throws {
        // R-3 — the move into Next needs what Next requires, so the note carries it.
        let waiting = TestVault.action(
            "Reference letter", .waiting, contexts: ["mac"], timeEstimate: 10,
            waiting: WaitingInfo(who: "Prof. Weber", followUp: TestVault.day(-9)),
            why: "The application needs it.", what: "Remind him.")
        let vault = TestVault.snapshot(actions: [waiting])
        let result = try Reducer.reduce(vault, .setStatus(waiting.id, status, waiting: nil), env: env)
        let action = try #require(result.snapshot.action(waiting.id))
        #expect(action.waitingFor == nil)
        #expect(action.followUpDate == nil)
    }

    // MARK: - D1 × R-2: defer and Next

    /// R-2 (reverses the 2026-09-19 refusal): a Next item may carry a future `defer`. It is
    /// hidden until its date and does not occupy a slot while hidden.
    @Test func aDeferredActionMayOccupyANextSlotAndIsHiddenUntilItsDate() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action(
            "Plan the timetable", .someday, contexts: ["mac"], timeEstimate: 30,
            why: "The semester starts.", what: "Draw it up.")])
        let id = TestVault.actionID("Plan the timetable")
        var deferred = try #require(vault.action(id))
        deferred.deferDate = TestVault.day(10)
        deferred.status = .next

        let result = try Reducer.reduce(vault, .updateAction(deferred), env: env)
        let stored = try #require(result.snapshot.action(id))
        #expect(stored.status == .next)
        #expect(stored.deferDate == TestVault.day(10))
        #expect(!Rules.isVisible(stored, today: env.today))
        #expect(Rules.nextList(result.snapshot, today: env.today).isEmpty)
        #expect(Rules.countsTowardCap(result.snapshot, today: env.today) == 0)
        // …and on its date it is back in Next, with the `back` badge.
        let onTheDay = TestVault.day(10)
        #expect(Rules.nextList(result.snapshot, today: onTheDay).map(\.id) == [id])
        #expect(Rules.countsTowardCap(result.snapshot, today: onTheDay) == 1)
        #expect(Rules.returnedFromDeferBadge(for: stored, today: onTheDay) != nil)
    }

    /// R-2 — a full Next plus a deferred Next item is legal: the hidden one holds no slot.
    /// When it returns, Next is simply over the cap; nothing is demoted automatically.
    @Test func aDeferredNextItemDoesNotConsumeASlotUntilItReturns() throws {
        let vault = TestVault.nextOccupied(15)
        let result = try Reducer.reduce(vault, .createAction(ActionDraft(
            title: "Später", status: .next, contexts: ["mac"], timeEstimate: 10,
            deferDate: TestVault.day(3), why: "Later, but committed.", what: "Do it.")), env: env)
        #expect(Rules.countsTowardCap(result.snapshot, today: env.today) == 15)
        #expect(Rules.capSignal(result.snapshot, today: env.today)?.step == .attention)

        let afterwards = TestVault.day(3)
        #expect(Rules.countsTowardCap(result.snapshot, today: afterwards) == 16)
        #expect(Rules.capSignal(result.snapshot, today: afterwards)
                == Signal(kind: .cap(count: 16, cap: 15), step: .overdue))
        // The over-cap list is never truncated — it must stay repairable.
        #expect(Rules.nextList(result.snapshot, today: afterwards).count == 16)
    }

    @Test func aDeferDateInThePastOrTodayIsFineInNext() throws {
        let vault = TestVault.snapshot()
        for offset in [-1, 0] {
            let result = try Reducer.reduce(vault, .createAction(ActionDraft(
                title: "Zurück \(offset)", status: .next, contexts: ["mac"], timeEstimate: 10,
                deferDate: TestVault.day(offset), why: "Committed.", what: "Do it.")), env: env)
            #expect(result.snapshot.actions.count == 1)
        }
    }

    /// A vault edited by hand into the contradiction stays editable — the rule refuses only the
    /// *new* contradiction.
    @Test func anExistingDeferredNextActionCanStillBeEdited() throws {
        // R-3 — a note already in Next with gaps stays editable; that is the point here.
        let stray = TestVault.action("Hand-edited", .next, deferDate: TestVault.day(10))
        let vault = TestVault.snapshot(actions: [stray])
        var edited = stray
        edited.why = "Repaired in the app"   // …even though it still has no What? (R-3)
        let result = try Reducer.reduce(vault, .updateAction(edited), env: env)
        #expect(result.snapshot.action(stray.id)?.why == "Repaired in the app")
        // …and demoting it works.
        let demoted = try Reducer.reduce(vault, .setStatus(stray.id, .someday, waiting: nil), env: env)
        #expect(demoted.snapshot.action(stray.id)?.status == .someday)
    }

    // MARK: - A4: contexts are a closed list

    @Test func unknownContextsAreRefusedAndDuplicatesCollapse() throws {
        let vault = TestVault.snapshot()
        #expect(TestVault.error(vault, .createAction(ActionDraft(
            title: "Mit Kontext", contexts: ["mac", "urgent"], what: "Tun")), env: env)
                == .invalid("Unknown context: urgent"))

        let result = try Reducer.reduce(vault, .createAction(ActionDraft(
            title: "Mit Kontext", contexts: ["mac", "mac", " phone "], what: "Tun")), env: env)
        #expect(result.snapshot.actions.first?.contexts == ["mac", "phone"])
    }

    /// A migrated note may carry a context the config does not know; editing it must not fail.
    @Test func contextsAlreadyInTheNoteSurviveAnEdit() throws {
        let legacy = TestVault.action("Alt", .someday, contexts: ["tum-stammgelände"])
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
            .createAction(ActionDraft(title: "Steuer/Erklärung: 2026?", what: "Anfangen")), env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.title == "Steuer Erklärung 2026")
        #expect(action.id.path == "Actions/Steuer Erklärung 2026.md")
        #expect(TestVault.error(
            TestVault.snapshot(), .createAction(ActionDraft(title: " \n ", what: "Tun")), env: env)
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
            .createAction(ActionDraft(
                title: "Ohne Schätzung", timeEstimate: estimate, what: "Tun")), env: env)
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
        vault.actions[0].status = .someday          // P3: it could not be in Next anyway
        let result = try Reducer.reduce(vault, .complete(vault.actions[0].id), env: env)
        #expect(result.prompts.isEmpty)
        #expect(result.snapshot.projects[0].log.count == 1)
    }

    // MARK: - I4c: trash is a move, not a status

    /// The note leaves the snapshot and nobody names its path, so the diff turns that into a
    /// `.delete`, which `GTDVault` performs as a move into `GTD/Trash/` (ARCHITECTURE §4).
    /// No `status: trash` is written anywhere.
    @Test func trashingAnActionRemovesItFromTheSnapshotAndWritesNoStatus() throws {
        let vault = TestVault.snapshot(actions: [TestVault.action("Podcast app", .someday)])
        let id = TestVault.actionID("Podcast app")
        let trashed = try Reducer.reduce(vault, .trashAction(id), env: env)
        #expect(trashed.snapshot.action(id) == nil)
        #expect(trashed.extraOps.isEmpty)      // the removed-entity rule owns the move
        #expect(TestVault.error(trashed.snapshot, .trashAction(id), env: env) == .notFound(id))
    }

    /// A promoted step must not keep pointing at a note that is now in the trash (T41).
    @Test func trashingAPromotedActionClearsTheStepLink() throws {
        var vault = projectVault()
        let action = vault.actions[0]
        vault.projects[0].steps = [ProjectStep(text: "Erste Schritte", promotedTo: action.id)]
        let result = try Reducer.reduce(vault, .trashAction(action.id), env: env)
        #expect(result.snapshot.projects[0].steps[0].promotedTo == nil)
    }

    /// R-1 — `status: trash` is a legacy state only. It can be read, it hides the note, and it
    /// can be repaired; nothing may move *into* it.
    @Test func theLegacyTrashStatusIsHiddenAndNotUserSettable() throws {
        let legacy = TestVault.action(
            "Podcast app", .legacyTrashed, contexts: ["mac"], timeEstimate: 10, completed: -30,
            why: "Legacy", what: "Legacy")
        let vault = TestVault.snapshot(actions: [legacy])
        #expect(!Rules.visibleActions(vault, today: env.today).contains { $0.id == legacy.id })
        #expect(!ActionStatus.allCases.contains(.legacyTrashed))

        // Nothing may move *into* it: an ordinary action cannot be given the legacy status.
        let open = TestVault.action("Noch offen", .someday)
        let mixed = TestVault.snapshot(actions: [legacy, open])
        #expect(TestVault.error(mixed, .setStatus(open.id, .legacyTrashed, waiting: nil), env: env)
                == .invalid("Trash is not a status — trashing moves the note to GTD/Trash/"))

        // Repairing it is allowed, and re-opening clears the closing date (A5, no lying date).
        let reopened = try Reducer.reduce(vault, .setStatus(legacy.id, .someday, waiting: nil), env: env)
        #expect(reopened.snapshot.action(legacy.id)?.status == .someday)
        #expect(reopened.snapshot.action(legacy.id)?.completedDate == nil)
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
            .trashAction(ghost),
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
        #expect(Rules.countsTowardCap(vault, today: env.today) == vault.config.nextCap - 1)

        let filled = try Reducer.reduce(
            vault, .createAction(ActionDraft(
                title: "Fifteenth", status: .next, contexts: ["mac"], timeEstimate: 10,
                why: "The last slot.", what: "Do it.")), env: env)
        #expect(Rules.countsTowardCap(filled.snapshot, today: env.today) == vault.config.nextCap)
        #expect(Rules.capSignal(filled.snapshot, today: env.today)?.step == .attention)

        #expect(TestVault.error(filled.snapshot, .createAction(ActionDraft(
            title: "Sixteenth", status: .next, contexts: ["mac"], timeEstimate: 10,
            why: "One too many.", what: "Do it.")), env: env)
                == .nextCapReached(cap: 15))
    }
}
