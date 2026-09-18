import Testing
import Foundation
import GTDModel
import GTDFixtures

/// I1, I4, I5 — every way a capture can leave the inbox, and every way it can be refused.
struct ReducerInboxTests {
    private let env = TestVault.env()
    private let capture = TestVault.inboxItem("2026-09-19 081204", "call the Hausverwaltung", created: 0)

    private func vault(
        actions: [Action] = [], projects: [Project] = [], areas: [Area] = []
    ) -> VaultSnapshot {
        TestVault.snapshot(inbox: [capture], actions: actions, areas: areas, projects: projects)
    }

    // MARK: - I4: the five decisions

    @Test func filingToAnActionCreatesTheNoteAndTrashesTheCapture() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .action(ActionDraft(
                title: "Call the Hausverwaltung", status: .next,
                contexts: ["calls"], timeEstimate: 10, what: "Call about the window handle"))),
            env: env)

        #expect(result.snapshot.inbox.isEmpty)
        let action = try #require(result.snapshot.action(TestVault.actionID("Call the Hausverwaltung")))
        #expect(action.status == .next)
        #expect(action.contexts == ["calls"])
        #expect(action.timeEstimate == 10)
        // The capture's timestamp is the action's `created` — nothing pretends to be new (C3).
        #expect(action.created == capture.created)
        #expect(action.modified == env.now)
        #expect(result.extraOps == [.delete(path: capture.id.path)])
    }

    @Test func filingToKnowledgeMovesTheCaptureFileItself() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .knowledge(folder: "Studium/Thesis", title: "Window handle")),
            env: env)

        #expect(result.snapshot.inbox.isEmpty)
        #expect(result.snapshot.actions.isEmpty)
        // I4: the capture *becomes* the knowledge note, keeping its text and `created`.
        #expect(result.extraOps == [.move(
            from: capture.id.path,
            to: "Knowledge/Studium/Thesis/Window handle.md")])
    }

    @Test func filingToANewProjectCreatesProjectAreaAndFirstActions() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .newProject(
                ProjectDraft(title: "Fenstergriff", newAreaTitle: "Wohnen",
                             outcome: "Handle replaced", steps: ["Call", "Order the part"]),
                firstActions: [ActionDraft(title: "Call the Hausverwaltung", status: .next)])),
            env: env)

        let area = try #require(result.snapshot.areas.first)
        #expect(area.title == "Wohnen")
        let project = try #require(result.snapshot.projects.first)
        #expect(project.area == area.id)
        #expect(project.status == .active)            // P3: a new project is active
        #expect(project.steps.map(\.text) == ["Call", "Order the part"])
        let action = try #require(result.snapshot.actions.first)
        #expect(action.project == project.id)
        #expect(result.prompts.isEmpty)
        #expect(result.extraOps == [.delete(path: capture.id.path)])
    }

    /// P4 — a project with no action would be born stalled, so the reducer asks for a step.
    @Test func aNewProjectWithoutFirstActionsAsksWhatsNext() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .newProject(
                ProjectDraft(title: "Fenstergriff", steps: ["Call"]), firstActions: [])),
            env: env)
        let project = try #require(result.snapshot.projects.first)
        #expect(result.prompts == [.whatsNext(project: project.id)])
    }

    @Test func filingToAnExistingProjectLinksEveryAction() throws {
        let project = TestVault.project("Wohnungssuche")
        let result = try Reducer.reduce(
            vault(projects: [project]),
            .fileInbox(capture.id, .existingProject(project.id, actions: [
                ActionDraft(title: "Call the Hausverwaltung", status: .next),
                ActionDraft(title: "Order the part", status: .backlog),
            ])),
            env: env)
        #expect(result.snapshot.actions.count == 2)
        #expect(result.snapshot.actions.allSatisfy { $0.project == project.id })
    }

    @Test func trashingOnlyMovesTheFile() throws {
        let result = try Reducer.reduce(vault(), .fileInbox(capture.id, .trash), env: env)
        #expect(result.snapshot.inbox.isEmpty)
        #expect(result.snapshot.actions.isEmpty)
        // `.delete` means "move to GTD/Trash/" — the app never hard-deletes (ARCHITECTURE §3).
        #expect(result.extraOps == [.delete(path: capture.id.path)])
    }

    // MARK: - I4: refusals

    @Test func filingIsRefusedWhenNextIsFull() throws {
        var full = TestVault.nextOccupied(15)
        full.inbox = [capture]
        let error = TestVault.error(full, .fileInbox(capture.id, .action(
            ActionDraft(title: "Call the Hausverwaltung", status: .next))), env: env)
        #expect(error == .nextCapReached(cap: 15))
    }

    @Test func filingToWaitingWithoutWhoIsRefused() {
        let error = TestVault.error(vault(), .fileInbox(capture.id, .action(
            ActionDraft(title: "Call the Hausverwaltung", status: .waiting))), env: env)
        #expect(error == .waitingInfoRequired)
    }

    @Test func aTitleThatAlreadyExistsIsACollision() {
        let existing = TestVault.action("Call the Hausverwaltung")
        let error = TestVault.error(vault(actions: [existing]), .fileInbox(capture.id, .action(
            ActionDraft(title: "Call the Hausverwaltung"))), env: env)
        #expect(error == .titleCollision("Call the Hausverwaltung"))
    }

    @Test func twoFirstActionsWithTheSameTitleCollide() {
        let error = TestVault.error(vault(), .fileInbox(capture.id, .newProject(
            ProjectDraft(title: "Fenstergriff"),
            firstActions: [ActionDraft(title: "Call"), ActionDraft(title: "Call")])), env: env)
        #expect(error == .titleCollision("Call"))
    }

    @Test func filingToAnUnknownProjectIsNotFound() {
        let missing = TestVault.layout.projectPath(title: "Ghost", inArea: nil)
        let error = TestVault.error(vault(), .fileInbox(capture.id, .existingProject(
            missing, actions: [ActionDraft(title: "Call")])), env: env)
        #expect(error == .notFound(missing))
    }

    /// The capture file is trashed by this decision, so it must produce at least one note.
    @Test func filingToAProjectWithoutAnyActionIsRefused() {
        let project = TestVault.project("Wohnungssuche")
        let error = TestVault.error(vault(projects: [project]),
                                    .fileInbox(capture.id, .existingProject(project.id, actions: [])),
                                    env: env)
        #expect(error == .invalid("Filing to a project needs at least one action"))
    }

    @Test func anEmptyTitleIsRefusedEverywhere() {
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .action(ActionDraft(title: "  "))), env: env)
                == .invalid("A title is required"))
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .knowledge(folder: "Studium", title: "")), env: env)
                == .invalid("A title is required"))
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .newProject(
            ProjectDraft(title: ""), firstActions: [])), env: env)
                == .invalid("A title is required"))
    }

    @Test func filingAnUnknownCaptureIsNotFound() {
        let ghost = TestVault.layout.inboxPath(stamp: "2000-01-01 000000")
        #expect(TestVault.error(vault(), .fileInbox(ghost, .trash), env: env) == .notFound(ghost))
        #expect(TestVault.error(vault(), .editInboxText(ghost, "x"), env: env) == .notFound(ghost))
        #expect(TestVault.error(vault(), .deferInboxToReview(ghost, reason: "x"), env: env) == .notFound(ghost))
    }

    /// A refused command must leave the vault exactly as it was.
    @Test func arefusedFilingChangesNothing() {
        var full = TestVault.nextOccupied(15)
        full.inbox = [capture]
        let before = full
        _ = TestVault.error(full, .fileInbox(capture.id, .action(
            ActionDraft(title: "Call the Hausverwaltung", status: .next))), env: env)
        #expect(full == before)
    }

    // MARK: - I5: defer to review

    @Test func deferToReviewStoresTheReasonAndLeavesTheQueue() throws {
        let result = try Reducer.reduce(
            vault(), .deferInboxToReview(capture.id, reason: "  It is a decision, not an action.  "), env: env)
        let item = try #require(result.snapshot.inboxItem(capture.id))
        #expect(item.reviewReason == "It is a decision, not an action.")
        #expect(Rules.inboxQueue(result.snapshot).isEmpty)
        #expect(Rules.reviewDeferredInbox(result.snapshot).map(\.id) == [capture.id])
        #expect(result.extraOps.isEmpty)
    }

    @Test func deferToReviewNeedsAReason() {
        #expect(TestVault.error(vault(), .deferInboxToReview(capture.id, reason: "   "), env: env)
                == .invalid("Defer to review needs a reason"))
    }

    @Test func editingTheCaptureTextKeepsEverythingElse() throws {
        let result = try Reducer.reduce(vault(), .editInboxText(capture.id, "call the Hausverwaltung today"), env: env)
        let item = try #require(result.snapshot.inboxItem(capture.id))
        #expect(item.text == "call the Hausverwaltung today")
        #expect(item.created == capture.created)
    }

    // MARK: - I1 against the realistic vault

    @Test func theSampleVaultProcessesLIFO() throws {
        let queue = Rules.inboxQueue(Fixtures.sampleSnapshot)
        #expect(queue.count == 5)                       // the sixth is deferred to review (I5)
        #expect(queue.first?.created == queue.map(\.created).max())
        let result = try Reducer.reduce(
            Fixtures.sampleSnapshot,
            .fileInbox(queue[0].id, .action(ActionDraft(title: "Neue Aufgabe", status: .backlog))),
            env: Fixtures.reducerEnv())
        #expect(Rules.inboxQueue(result.snapshot).map(\.id) == Array(queue.dropFirst()).map(\.id))
    }
}
